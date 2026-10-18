import { createServer } from 'node:http';
import { randomBytes } from 'node:crypto';
import { readFile, writeFile, appendFile, mkdir } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { createChatGPT } from './vendor/sign-in-with-chatgpt-devkit/packages/local/dist/index.js';
import { authenticated, completeChat, supportedEfforts } from './adapter.mjs';
import { resolveDataDir } from './data-dir.mjs';

const root = dirname(fileURLToPath(import.meta.url));
const dataDir = resolveDataDir(root);
await mkdir(dataDir, { recursive: true });
const settingsPath = join(dataDir, 'bridge.json');
let settings;
try { settings = JSON.parse(await readFile(settingsPath, 'utf8')); }
catch (error) {
  if (error.code !== 'ENOENT') throw error;
  settings = { apiKey: randomBytes(32).toString('hex'), model: 'gpt-6.1-sol' };
  await writeFile(settingsPath, JSON.stringify(settings, null, 2), { mode: 0o600, flag: 'wx' });
}
const port = 8766;
settings.effort ??= 'default';
function effortSettings() { return { effort: settings.effort, efforts: supportedEfforts(settings.model) }; }
const origin = `http://127.0.0.1:${port}`;
const csrf = randomBytes(32).toString('hex');

function dpapi(operation, bytes) {
  return new Promise((resolve, reject) => {
    const child = spawn('powershell.exe', ['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',join(root,'dpapi.ps1'),operation], {
      windowsHide: true, stdio: ['pipe','pipe','pipe'],
    });
    const chunks = [];
    child.stdout.on('data', chunk => chunks.push(chunk));
    child.stderr.resume();
    child.on('error', () => reject(new Error('Windows credential encryption is unavailable.')));
    child.on('close', code => code === 0
      ? resolve(Buffer.from(Buffer.concat(chunks).toString().trim(), 'base64'))
      : reject(new Error('Windows credential encryption failed.')));
    child.stdin.on('error', () => {});
    child.stdin.end(Buffer.from(bytes).toString('base64'));
  });
}

let authorizationUrl;
let loginError;
let loginPromise;
let loginStartedAt;
let catalog = [];
let catalogTime = 0;
let completedRequests = 0;
const usageTotals = { reportedRequests: 0, missingUsageRequests: 0, inputTokens: 0, outputTokens: 0, totalTokens: 0, cachedInputTokens: 0, reasoningTokens: 0 };
async function recordUsage(completion, startedAt) {
  const usage = completion.usage;
  if (usage) {
    usageTotals.reportedRequests++;
    usageTotals.inputTokens += usage.prompt_tokens;
    usageTotals.outputTokens += usage.completion_tokens;
    usageTotals.totalTokens += usage.total_tokens;
    usageTotals.cachedInputTokens += usage.prompt_tokens_details?.cached_tokens ?? 0;
    usageTotals.reasoningTokens += usage.completion_tokens_details?.reasoning_tokens ?? 0;
  } else usageTotals.missingUsageRequests++;
  // Numeric measurements only: no credentials, prompts or translated text.
  try {
    await appendFile(join(dataDir,'usage.jsonl'), JSON.stringify({ at:new Date().toISOString(), id:completion.id, model:completion.model, durationMs:Date.now()-startedAt, usage:usage ?? null })+'\n');
  } catch { console.error('Could not persist usage measurement; in-memory totals remain available.'); }
}
let lastTest;
let inFlight = 0;
let stopping = false;
let peakInFlight = 0;
const maxConcurrentRequests = 4;
const client = createChatGPT({
  appName: 'Zotero PDF2zh ChatGPT Bridge', appId: 'zotero-pdf2zh-chatgpt-bridge',
  redirectPort: 0, storageDir: join(dataDir, 'account'), sendHostId: true,
  credentialEncryption: {
    id: 'windows-dpapi-current-user-v1', isAvailable: () => process.platform === 'win32',
    encrypt: text => dpapi('encrypt', Buffer.from(text)),
    decrypt: async bytes => (await dpapi('decrypt', bytes)).toString('utf8'),
  },
  openBrowser: url => { authorizationUrl = url; },
});

async function models() {
  if (!catalog.length || Date.now() - catalogTime > 300000) {
    catalog = await client.listModels(); catalogTime = Date.now();
  }
  return catalog;
}

async function selectedModel(requested) {
  const list = await models();
  const selected = !requested || requested === 'chatgpt-auto' ? settings.model : requested;
  if (!list.some(model => model.slug === selected)) {
    throw Object.assign(new Error('所选模型不在当前账号目录中，请在本机连接页面重新选择模型。'), { status: 400 });
  }
  return selected;
}

function json(res, status, body) {
  res.writeHead(status, { 'Content-Type':'application/json; charset=utf-8', 'Cache-Control':'no-store' });
  res.end(JSON.stringify(body));
}

async function bodyJson(req) {
  let size = 0; const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 2 * 1024 * 1024) throw Object.assign(new Error('Request too large.'), { status: 413 });
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'); }
  catch { throw Object.assign(new Error('Invalid JSON.'), { status: 400 }); }
}

const server = createServer(async (req, res) => {
  try {
    if (req.headers.host !== `127.0.0.1:${port}` || (req.headers.origin && req.headers.origin !== origin)) {
      return json(res, 403, { error: { message: 'Local origin required.' } });
    }
    const path = new URL(req.url, origin).pathname;
    if (stopping) return json(res,503,{error:{message:'Service is stopping.'}});
    if (req.method === 'GET' && path === '/') {
      const page = (await readFile(join(root,'index.html'),'utf8')).replaceAll('__CSRF__',csrf);
      res.writeHead(200, { 'Content-Type':'text/html; charset=utf-8', 'Cache-Control':'no-store',
        'Content-Security-Policy': "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'" });
      return res.end(page);
    }
    if (req.method === 'GET' && path === '/status') {
      const session = await client.getSession();
      return json(res,200,{ app:'zotero-pdf2zh-chatgpt-bridge',dataDir,session,model:settings.model,
        completedRequests,usageTotals,inFlight,peakInFlight,maxConcurrentRequests,lastTest,loginError,loginExpiresAt:loginPromise ? loginStartedAt + 600000 : null });
    }
    if (req.method === 'GET' && path === '/models') return json(res,200,{models:await models(),selected:settings.model,...effortSettings()});
    if (path.startsWith('/v1/')) {
      if (!authenticated(req.headers.authorization, settings.apiKey)) return json(res,401,{error:{message:'Invalid local API key.'}});
      if (req.method === 'POST' && path === '/v1/shutdown') {
        if (inFlight || loginPromise) return json(res,409,{error:{message:'Translation or login is still running. Wait for it to finish.'}});
        stopping = true;
        json(res,200,{status:'stopping'});
        setTimeout(() => { server.close(); server.closeAllConnections(); },500);
        return;
      }
      if (req.method === 'GET' && path === '/v1/models') {
        return json(res,200,{object:'list',data:(await models()).map(m=>({id:m.slug,object:'model',owned_by:'openai'}))});
      }
      if (req.method === 'POST' && path === '/v1/chat/completions') {
        const body = await bodyJson(req);
        // Reserve the slot after reading the body, with no await between the check and increment.
        if (inFlight >= maxConcurrentRequests) {
          res.setHeader('Retry-After','1');
          return json(res,429,{error:{code:'local_concurrency_limit',message:`${maxConcurrentRequests} translations are already running. Use at most ${maxConcurrentRequests} PDF2zh workers.`}});
        }
        const controller = new AbortController();
        res.on('close',()=>{if(!res.writableEnded)controller.abort();});
        inFlight++;
        peakInFlight = Math.max(peakInFlight,inFlight);
        try {
          const startedAt = Date.now();
          const model = await selectedModel(body.model);
          const completion = await completeChat(client,body,model,controller.signal,settings.effort);
          completedRequests++;
          await recordUsage(completion,startedAt);
          return json(res,200,completion);
        } finally { inFlight--; }
      }
      return json(res,404,{error:{message:'Unsupported API endpoint.'}});
    }
    if (req.method !== 'POST') return json(res,404,{error:{message:'Not found.'}});
    if (req.headers['x-csrf-token'] !== csrf) return json(res,403,{error:{message:'Reopen the local connection page.'}});
    if (path === '/login') {
      if (!loginPromise) {
        loginError = undefined; authorizationUrl = undefined;
        loginStartedAt = Date.now();
        loginPromise = client.signIn().catch(error=>{
          loginError = error.code === 'cancelled' && Date.now() - loginStartedAt >= 599000
            ? {code:'login_expired',message:'登录请求已超过 10 分钟有效期。请重新点击 Continue with ChatGPT，并在新打开的页面完成授权；旧回调页面已失效。'}
            : {code:error.code,message:error.message};
        })
          .finally(()=>{loginPromise=undefined;authorizationUrl=undefined;catalog=[];});
      }
      return json(res,202,{starting:true});
    }
    if (path === '/login-url') return json(res,200,{url:authorizationUrl,error:loginError});
    if (path === '/model') {
      const { model } = await bodyJson(req);
      settings.model = await selectedModel(model);
      if (!supportedEfforts(settings.model).includes(settings.effort)) settings.effort = 'default';
      await writeFile(settingsPath,JSON.stringify(settings,null,2),{mode:0o600});
      return json(res,200,{model:settings.model,...effortSettings()});
    }
    if (path === '/effort') {
      const { effort } = await bodyJson(req);
      if (!supportedEfforts(settings.model).includes(effort)) return json(res,400,{error:{message:'所选模型不支持此推理强度。'}});
      await writeFile(settingsPath,JSON.stringify({...settings,effort},null,2),{mode:0o600});
      settings.effort = effort;
      return json(res,200,effortSettings());
    }
    if (path === '/test') {
      inFlight++;
      try {
      const startedAt = Date.now();
      const model = await selectedModel('chatgpt-auto');
      const response = await completeChat(client,{messages:[
        {role:'system',content:'Translate into Simplified Chinese. Return only the translation.'},
        {role:'user',content:'The proposed method improves indoor localization accuracy.'},
      ]},model,AbortSignal.timeout(180000),settings.effort);
      lastTest={model,effort:settings.effort,text:response.choices[0].message.content,at:new Date().toISOString()};
      completedRequests++;
      await recordUsage(response,startedAt);
      return json(res,200,lastTest);
      } finally { inFlight--; }
    }
    return json(res,404,{error:{message:'Not found.'}});
  } catch (error) {
    // Prevent PDF2zh's long 429 retry loop when the subscription allowance is exhausted.
    const exhausted = /subscription_sharing_usage|usage_limit|sharing_not_enabled|sign_in_required/.test(error.code || '');
    const status = exhausted ? 403 : (error.status >= 400 && error.status <= 599 ? error.status : 502);
    if (!res.headersSent) json(res,status,{error:{code:error.code || 'bridge_error',message:error.message,
      usage_url:'https://chatgpt.com/settings/usage'}});
    else res.end();
  }
});
server.listen(port,'127.0.0.1',()=>console.log(`Zotero ChatGPT bridge listening at ${origin}`));
