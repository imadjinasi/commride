// Minimal D1Database backed by Node's built-in SQLite, with every migration
// applied. Lets repository tests exercise the real schema and SQL.
// Node modules are loaded dynamically because the API compiles against
// Worker types only.

interface SqliteStatement {
  all(...params: unknown[]): unknown[];
  get(...params: unknown[]): unknown;
  run(...params: unknown[]): { changes: number | bigint };
}

interface SqliteDatabase {
  exec(sql: string): void;
  prepare(sql: string): SqliteStatement;
}

class SqlitePreparedStatement {
  constructor(
    private readonly database: SqliteDatabase,
    readonly sql: string,
    readonly params: readonly unknown[] = [],
  ) {}

  bind(...params: unknown[]): SqlitePreparedStatement {
    return new SqlitePreparedStatement(this.database, this.sql, params);
  }

  async first<T>(): Promise<T | null> {
    return (this.statement().get(...this.params) as T | undefined) ?? null;
  }

  async all<T>(): Promise<{ results: T[] }> {
    return { results: this.statement().all(...this.params) as T[] };
  }

  async run(): Promise<{ meta: { changes: number } }> {
    return { meta: this.runSync() };
  }

  runSync(): { changes: number } {
    const result = this.statement().run(...this.params);
    return { changes: Number(result.changes) };
  }

  private statement(): SqliteStatement {
    return this.database.prepare(this.sql);
  }
}

export interface SqliteD1 {
  readonly d1: D1Database;
  query<T>(sql: string, ...params: unknown[]): T[];
  exec(sql: string): void;
}

export async function createSqliteD1(): Promise<SqliteD1> {
  const sqliteModule: string = 'node:sqlite';
  const fsModule: string = 'node:fs';
  const { DatabaseSync } = await import(sqliteModule);
  const { readdirSync, readFileSync } = await import(fsModule);

  const database: SqliteDatabase = new DatabaseSync(':memory:');
  database.exec('PRAGMA foreign_keys = ON');

  const migrationsDir = new URL('../../migrations/', import.meta.url);
  const files = (readdirSync(migrationsDir) as string[])
    .filter((name) => name.endsWith('.sql'))
    .sort();
  for (const file of files) {
    database.exec(readFileSync(new URL(file, migrationsDir), 'utf8'));
  }

  const d1 = {
    prepare: (sql: string) => new SqlitePreparedStatement(database, sql),
    batch: async (statements: SqlitePreparedStatement[]) => {
      database.exec('BEGIN');
      try {
        const results = statements.map((statement) => ({
          meta: statement.runSync(),
        }));
        database.exec('COMMIT');
        return results;
      } catch (error) {
        database.exec('ROLLBACK');
        throw error;
      }
    },
  } as unknown as D1Database;

  return {
    d1,
    query: <T>(sql: string, ...params: unknown[]) =>
      database.prepare(sql).all(...params) as T[],
    exec: (sql: string) => database.exec(sql),
  };
}
