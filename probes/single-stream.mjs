// Executable specification only: one uninterrupted process, one progress stream.
// No transport, audio, persistence, tap, pause, expiry or retry policy is implied.
export class SingleStream {
  #active = null;
  #pending = null;
  #seen = new Map();
  accept(id, text) {
    if (typeof id !== 'string' || !id.trim() || typeof text !== 'string' || !text.trim()) {
      throw new TypeError('id and text must be non-empty strings');
    }
    if (this.#seen.has(id)) {
      if (this.#seen.get(id) !== text) throw new Error('id reused with different text');
      return {status: 'duplicate'};
    }
    const replaced = this.#pending?.id ?? null;
    this.#seen.set(id, text);
    this.#pending = Object.freeze({id, text});
    return {status: 'accepted', replaced};
  }
  begin() {
    if (this.#active || !this.#pending) return null;
    this.#active = this.#pending;
    this.#pending = null;
    return this.#active;
  }
  complete(id) {
    if (!this.#active || this.#active.id !== id) throw new Error('completion does not match active playback');
    this.#active = null;
  }
}
