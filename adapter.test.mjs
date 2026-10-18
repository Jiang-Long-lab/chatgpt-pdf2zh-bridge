import test from 'node:test';
import assert from 'node:assert/strict';
import { authenticated, completeChat, toResponseInput } from './adapter.mjs';

test('explicit effort reaches SDK; default omitted; unsupported effort rejected',async()=>{
  let seen;
  const client={streamResponse:async options=>{seen=options;return {text:'译文'};}};
  const body={messages:[{role:'user',content:'Translate.'}]};
  await completeChat(client,body,'gpt-6.1-sol',undefined,'low');
  assert.equal(seen.reasoningEffort,'low');
  await completeChat(client,body,'gpt-6-luna',undefined,'none');
  assert.equal(seen.reasoningEffort,'none');
  await completeChat(client,body,'gpt-6.1-sol');
  assert.equal('reasoningEffort' in seen,false);
  await assert.rejects(completeChat(client,body,'gpt-6.1-sol',undefined,'none'),{status:400});
});

test('preserves PDF2zh instructions and translation placeholders', async()=>{
  let seen;
  const client={streamResponse:async value=>{seen=value;return {text:'该方法保留 {v0}。'};}};
  const result=await completeChat(client,{messages:[{role:'system',content:'Preserve {v0}.'},{role:'user',content:'The method preserves {v0}.'}]},'selected-model');
  assert.equal(seen.instructions,'Preserve {v0}.');
  assert.equal(seen.input[0].content,'The method preserves {v0}.');
  assert.equal(result.choices[0].message.content,'该方法保留 {v0}。');
  assert.equal(result.model,'selected-model');
  assert.equal(result.usage,undefined);
});
test('forwards server-reported usage with cached and reasoning details',async()=>{
  const result=await completeChat({streamResponse:async()=>({text:'译文',usage:{input_tokens:100,output_tokens:20,total_tokens:120,input_tokens_details:{cached_tokens:64},output_tokens_details:{reasoning_tokens:5}}})},{messages:[{role:'user',content:'x'}]},'m');
  assert.deepEqual(result.usage,{prompt_tokens:100,completion_tokens:20,total_tokens:120,prompt_tokens_details:{cached_tokens:64},completion_tokens_details:{reasoning_tokens:5}});
});
test('never turns failed or empty inference into a completed translation',async()=>{
  await assert.rejects(completeChat({streamResponse:async()=>{throw new Error('stream_interrupted');}},{messages:[{role:'user',content:'x'}]},'m'),/stream_interrupted/);
  await assert.rejects(completeChat({streamResponse:async()=>({text:' '})},{messages:[{role:'user',content:'x'}]},'m'),/empty response/);
});
test('rejects unsupported payloads and invalid local credentials',()=>{
  assert.throws(()=>toResponseInput({messages:[{role:'tool',content:'x'}]}));
  assert.throws(()=>toResponseInput({messages:[{role:'user',content:'x'}],response_format:{type:'json_object'}}));
  assert.equal(authenticated(undefined,'secret'),false);
  assert.equal(authenticated('Bearer incorrect','secret'),false);
  assert.equal(authenticated('Bearer secret','secret'),true);
});
