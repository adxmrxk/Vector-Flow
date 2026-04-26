/**
 * VectorFlow TypeScript Type Definitions
 * Strictly typed interfaces for API communication
 */

// ----- API Request Types -----

export interface EmbeddingRequest {
  texts: string[];
  normalize?: boolean;
}

export interface SearchRequest {
  query: string;
  topK?: number;
  namespace?: string;
  filter?: Record<string, unknown>;
  includeMetadata?: boolean;
}

export interface UpsertRequest {
  id: string;
  text: string;
  metadata?: Record<string, unknown>;
  namespace?: string;
}

export interface BatchUpsertRequest {
  vectors: UpsertRequest[];
}

// ----- API Response Types -----

export interface EmbeddingResponse {
  embeddings: number[][];
  model: string;
  dimension: number;
  usage: {
    totalTexts: number;
    estimatedTokens: number;
  };
}

export interface SearchResult {
  id: string;
  score: number;
  metadata?: Record<string, unknown>;
}

export interface SearchResponse {
  results: SearchResult[];
  query: string;
  totalResults: number;
  latencyMs: number;
}

export interface UpsertResponse {
  upsertedCount: number;
  ids: string[];
}

export interface HealthResponse {
  status: 'healthy' | 'unhealthy';
  version: string;
  modelLoaded: boolean;
  pineconeConnected: boolean;
  timestamp: string;
}

export interface ModelInfo {
  modelName: string;
  dimension: number;
  maxSequenceLength: number;
  device: string;
  loaded: boolean;
}

export interface IndexInfo {
  dimension: number;
  totalVectorCount: number;
  namespaces: Record<string, { vectorCount: number }>;
}

export interface ErrorResponse {
  error: string;
  message: string;
  detail?: string;
  timestamp: string;
}

// ----- UI State Types -----

export interface SearchState {
  query: string;
  results: SearchResult[];
  isLoading: boolean;
  error: string | null;
  latencyMs: number | null;
}

export interface SystemStatus {
  gateway: ServiceStatus;
  worker: ServiceStatus;
  inference: ServiceStatus;
}

export interface ServiceStatus {
  name: string;
  status: 'online' | 'offline' | 'degraded';
  latencyMs?: number;
  lastChecked: Date;
}

// ----- Utility Types -----

export type ApiResult<T> =
  | { success: true; data: T }
  | { success: false; error: ErrorResponse };

export type LoadingState = 'idle' | 'loading' | 'success' | 'error';
