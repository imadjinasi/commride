declare module 'node:crypto' {
  export interface KeyObject {
    readonly type: 'secret' | 'public' | 'private';
  }

  export function createPublicKey(key: string): KeyObject;

  export function verify(
    algorithm: string,
    data: ArrayBufferView<ArrayBuffer>,
    key: KeyObject,
    signature: ArrayBufferView<ArrayBuffer>,
  ): boolean;
}
