// Minimal type surface for sql.js — we only use Database.run/export/close.
declare module "sql.js" {
  export interface SqlJsStatic {
    Database: {
      new (data?: Uint8Array): Database;
    };
  }
  export interface Database {
    run(sql: string, params?: unknown[]): void;
    export(): Uint8Array;
    close(): void;
  }
  export interface InitOptions {
    wasmBinary?: Uint8Array | ArrayBuffer;
    locateFile?: (file: string) => string;
  }
  export default function initSqlJs(
    options?: InitOptions
  ): Promise<SqlJsStatic>;
}
