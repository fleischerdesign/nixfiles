/**
 * Ambient module declarations for optional heavy runtime dependencies that are
 * lazily imported and may not be present in every build/lint environment. This
 * keeps TypeScript tolerant of the optional @huggingface/transformers dependency
 * (the ONNX embedding provider) until it is actually vendored into the store.
 */
declare module '@huggingface/transformers' {
  export const env: {
    cacheDir?: string;
    allowRemoteModels?: boolean;
    allowLocalModels?: boolean;
    useBrowserCache?: boolean;
  };
  export function pipeline(
    task: string,
    model?: string,
    options?: Record<string, unknown>,
  ): Promise<any>;
}
