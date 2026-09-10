import {test} from 'node:test';
import assert from 'node:assert/strict';
import {SingleStream} from '../probes/single-stream.mjs';
test('A finishes; B is superseded by C; only C follows A', () => {
  const q = new SingleStream();
  q.accept('A', '確認してるよ。');
  assert.equal(q.begin().id, 'A');
  q.accept('B', '原因候補だよ。');
  assert.equal(q.accept('C', 'まだ未検証だよ。').replaced, 'B');
  assert.equal(q.begin(), null);
  q.complete('A');
  assert.deepEqual(q.begin(), {id:'C', text:'まだ未検証だよ。'});
  q.complete('C');
  assert.equal(q.begin(), null);
});
test('duplicates cannot requeue active, superseded or completed notifications', () => {
  const q = new SingleStream();
  q.accept('A', 'a'); q.begin();
  q.accept('B', 'b'); q.accept('C', 'c');
  for (const [id,text] of [['A','a'],['B','b'],['C','c']]) assert.equal(q.accept(id,text).status,'duplicate');
  q.complete('A'); assert.equal(q.begin().id,'C'); q.complete('C');
  assert.equal(q.accept('C','c').status,'duplicate');
  assert.equal(q.begin(),null);
});
test('conflicting duplicate and stale completion leave pending state intact', () => {
  const q = new SingleStream(); q.accept('A','a'); q.begin(); q.accept('B','b');
  assert.throws(()=>q.accept('B','changed'));
  assert.throws(()=>q.complete('B'));
  assert.equal(q.begin(),null); q.complete('A');
  assert.deepEqual(q.begin(),{id:'B',text:'b'});
});
test('reject malformed input without creating work', () => {
  const q = new SingleStream();
  assert.throws(()=>q.accept('', 'a')); assert.throws(()=>q.accept('a',' '));
  assert.equal(q.begin(),null);
});
