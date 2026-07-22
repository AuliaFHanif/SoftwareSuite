import { appendFile, existsSync, mkdirSync, writeFile } from 'fs';
import { promisify } from 'util';
import path from 'path';

const appendFileAsync = promisify(appendFile);
const writeFileAsync = promisify(writeFile);

export type LogLevel = 'INFO' | 'WARN' | 'ERROR' | 'DEBUG';
export type RequestType = 'FILE' | 'TEXT' | 'IMAGE';

export interface LogEntry {
  timestamp: string;
  requestId: string;
  level: LogLevel;
  phase: 'START' | 'PROCESSING' | 'COMPLETED' | 'ERROR';
  type: RequestType;
  step: string;
  message: string;
  duration?: number;
  totalDurationMs?: number;
  metadata?: Record<string, unknown>;
}

const LOG_FILE_PATH = path.join(process.cwd(), 'logs', 'translation-log.csv');
const CSV_HEADERS = ['timestamp', 'type', 'phase', 'step', 'message', 'duration_ms', 'totalDurationMs'];

let initPromise: Promise<void> | null = null;

async function ensureLogFile(): Promise<void> {
  if (initPromise) return initPromise;

  initPromise = (async () => {
    try {
      const dir = path.dirname(LOG_FILE_PATH);
      if (!existsSync(dir)) {
        mkdirSync(dir, { recursive: true });
      }
      if (!existsSync(LOG_FILE_PATH)) {
        await writeFileAsync(LOG_FILE_PATH, CSV_HEADERS.join(',') + '\n');
      }
    } catch (error) {
      console.error('Failed to create log file:', error);
    }
  })();

  return initPromise;
}

async function appendToCSV(entry: LogEntry): Promise<void> {
  try {
    await ensureLogFile();
    const messageStr = String(entry.message || '');
    const stepStr = String(entry.step || '');
    const row = [
      entry.timestamp,
      entry.type,
      entry.phase,
      `"${stepStr.replace(/"/g, '""')}"`,
      `"${messageStr.replace(/"/g, '""')}"`,
      entry.duration?.toString() || '',
      entry.totalDurationMs?.toString() || '',
    ].join(',');
    await appendFileAsync(LOG_FILE_PATH, row + '\n');
  } catch (error) {
    console.error('Failed to write to log file:', error);
  }
}

class RequestLogger {
  private logs: LogEntry[] = [];
  private requestId: string;
  private startTime: number;
  private requestType: RequestType;

  constructor(type: RequestType, requestId?: string) {
    this.requestId = requestId || generateRequestId();
    this.startTime = Date.now();
    this.requestType = type;
  }

  getRequestId(): string {
    return this.requestId;
  }

  getRequestType(): RequestType {
    return this.requestType;
  }

  log(
    level: LogLevel,
    phase: LogEntry['phase'],
    step: string,
    message: string,
    metadata?: Record<string, unknown>
  ): void {
    const entry: LogEntry = {
      timestamp: new Date().toISOString(),
      requestId: this.requestId,
      level,
      phase,
      type: this.requestType,
      step,
      message,
      duration: Date.now() - this.startTime,
      metadata,
    };
    this.logs.push(entry);

    // Console output
    const prefix = `[${entry.timestamp}] [${entry.type}] [${level}] [${phase}]`;
    if (level === 'ERROR') {
      console.error(`${prefix} [${step}] ${message}`, metadata || '');
    } else {
      console.log(`${prefix} [${step}] ${message}`, metadata || '');
    }

    // Write to CSV file (async, non-blocking)
    appendToCSV(entry).catch(() => {});
  }

  info(phase: LogEntry['phase'], step: string, message: string, metadata?: Record<string, unknown>): void {
    this.log('INFO', phase, step, message, metadata);
  }

  warn(phase: LogEntry['phase'], step: string, message: string, metadata?: Record<string, unknown>): void {
    this.log('WARN', phase, step, message, metadata);
  }

  error(phase: LogEntry['phase'], step: string, message: string, metadata?: Record<string, unknown>): void {
    this.log('ERROR', phase, step, message, metadata);
  }

  debug(phase: LogEntry['phase'], step: string, message: string, metadata?: Record<string, unknown>): void {
    this.log('DEBUG', phase, step, message, metadata);
  }

  complete(message: string = '', metadata?: Record<string, unknown>): void {
    const totalDuration = Date.now() - this.startTime;
    this.log('INFO', 'COMPLETED', 'Request Complete', message, {
      totalDurationMs: totalDuration,
      ...metadata,
    });
    this.logs.forEach(log => {
      log.totalDurationMs = totalDuration;
    });
  }

  getLogs(): LogEntry[] {
    return [...this.logs];
  }

  toCSV(): string {
    const rows = this.logs.map(log => {
      const messageStr = String(log.message || '');
      const stepStr = String(log.step || '');
      return [
        log.timestamp,
        log.type,
        log.phase,
        `"${stepStr.replace(/"/g, '""')}"`,
        `"${messageStr.replace(/"/g, '""')}"`,
        log.duration?.toString() || '',
        log.totalDurationMs?.toString() || '',
      ];
    });
    return [CSV_HEADERS.join(','), ...rows.map(row => row.join(','))].join('\n');
  }

  toJSON(): string {
    return JSON.stringify({
      requestId: this.requestId,
      requestType: this.requestType,
      totalDuration: Date.now() - this.startTime,
      logs: this.logs,
    }, null, 2);
  }

  getSummary(): { requestId: string; requestType: RequestType; totalDuration: number; logCount: number } {
    return {
      requestId: this.requestId,
      requestType: this.requestType,
      totalDuration: Date.now() - this.startTime,
      logCount: this.logs.length,
    };
  }
}

function generateRequestId(): string {
  return `req_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
}

export function createLogger(type: RequestType): RequestLogger {
  return new RequestLogger(type);
}

export function createTrackedLogger(): RequestLogger {
  return new RequestLogger('FILE');
}

export function getLogFilePath(): string {
  return LOG_FILE_PATH;
}