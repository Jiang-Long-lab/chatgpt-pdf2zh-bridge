import { randomUUID, timingSafeEqual } from 'node:crypto';

export function authenticated(header, key) {
  const received = Buffer.from(header || '');
  const expected = Buffer.from(`Bearer ${key}`);
  return received.length === expected.length && timingSafeEqual(received, expected);
}

export function toResponseInput(body) {
  if (!body || !Array.isArray(body.messages) || !body.messages.length || body.stream) {
    throw Object.assign(new Error('PDF2zh bridge requires non-streaming text chat messages.'), { status: 400 });
  }
  const input = [];
  const instructions = [];
  for (const message of body.messages) {
    if (!message || typeof message.content !== 'string' || !['system','developer','user','assistant'].includes(message.role)) {
      throw Object.assign(new Error('Only text messages are supported.'), { status: 400 });
    }
    if (message.role === 'system') instructions.push(message.content);
    else input.push({ role: message.role, content: message.content });
  }
  if (!input.length) throw Object.assign(new Error('A user message is required.'), { status: 400 });
  if (body.response_format && body.response_format.type !== 'text') {
    throw Object.assign(new Error('Disable JSON mode in PDF2zh for this bridge.'), { status: 400 });
  }
  return { input, ...(instructions.length ? { instructions: instructions.join('\n\n') } : {}) };
}

export function supportedEfforts(model) {
  const levels = ['default','low','medium','high','xhigh','max'];
  if (['gpt-6-sol','gpt-6-luna'].includes(model)) return ['default','none',...levels.slice(1)];
  return ['gpt-6.1-sol','gpt-6-astra'].includes(model) ? levels : ['default'];
}

export async function completeChat(client, body, model, signal, effort = 'default') {
  if (!supportedEfforts(model).includes(effort)) throw Object.assign(new Error('所选模型不支持此推理强度。'), { status: 400 });
  const options = toResponseInput(body);
  // The official SDK validates response.completed; partial/failed output is never returned as a translation.
  const result = await client.streamResponse({ ...options, model, signal, ...(effort !== 'default' ? { reasoningEffort: effort } : {}) });
  if (!result.text.trim()) throw Object.assign(new Error('ChatGPT returned an empty response.'), { status: 502 });
  return {
    id: `chatcmpl-${randomUUID()}`, object: 'chat.completion', created: Math.floor(Date.now() / 1000), model,
    choices: [{ index: 0, message: { role: 'assistant', content: result.text }, finish_reason: 'stop' }],
    ...(result.usage ? { usage: {
      prompt_tokens: result.usage.input_tokens,
      completion_tokens: result.usage.output_tokens,
      total_tokens: result.usage.total_tokens,
      ...(result.usage.input_tokens_details ? { prompt_tokens_details: result.usage.input_tokens_details } : {}),
      ...(result.usage.output_tokens_details ? { completion_tokens_details: result.usage.output_tokens_details } : {}),
    } } : {}),
  };
}
