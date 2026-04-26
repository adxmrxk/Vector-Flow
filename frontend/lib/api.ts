/**
 * VectorFlow API Client
 * Type-safe API calls to the Go Gateway
 */

import type {
  ApiResult,
  BatchUpsertRequest,
  EmbeddingRequest,
  EmbeddingResponse,
  ErrorResponse,
  HealthResponse,
  IndexInfo,
  ModelInfo,
  SearchRequest,
  SearchResponse,
  UpsertRequest,
  UpsertResponse,
} from './types';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080';

class ApiClient {
  private baseUrl: string;

  constructor(baseUrl: string = API_URL) {
    this.baseUrl = baseUrl;
  }

  private async request<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<ApiResult<T>> {
    try {
      const response = await fetch(`${this.baseUrl}${endpoint}`, {
        ...options,
        headers: {
          'Content-Type': 'application/json',
          ...options.headers,
        },
      });

      const data = await response.json();

      if (!response.ok) {
        return {
          success: false,
          error: data as ErrorResponse,
        };
      }

      return {
        success: true,
        data: data as T,
      };
    } catch (error) {
      return {
        success: false,
        error: {
          error: 'NetworkError',
          message: error instanceof Error ? error.message : 'Unknown error',
          timestamp: new Date().toISOString(),
        },
      };
    }
  }

  // ----- Health Endpoints -----

  async health(): Promise<ApiResult<HealthResponse>> {
    return this.request<HealthResponse>('/health');
  }

  async ready(): Promise<ApiResult<{ status: string }>> {
    return this.request<{ status: string }>('/ready');
  }

  // ----- Embedding Endpoints -----

  async createEmbeddings(
    request: EmbeddingRequest
  ): Promise<ApiResult<EmbeddingResponse>> {
    return this.request<EmbeddingResponse>('/v1/embeddings', {
      method: 'POST',
      body: JSON.stringify(request),
    });
  }

  // ----- Search Endpoints -----

  async search(request: SearchRequest): Promise<ApiResult<SearchResponse>> {
    return this.request<SearchResponse>('/v1/search', {
      method: 'POST',
      body: JSON.stringify({
        query: request.query,
        top_k: request.topK ?? 10,
        namespace: request.namespace,
        filter: request.filter,
        include_metadata: request.includeMetadata ?? true,
      }),
    });
  }

  // ----- Upsert Endpoints -----

  async upsert(request: UpsertRequest): Promise<ApiResult<UpsertResponse>> {
    return this.request<UpsertResponse>('/v1/upsert', {
      method: 'POST',
      body: JSON.stringify(request),
    });
  }

  async batchUpsert(
    request: BatchUpsertRequest
  ): Promise<ApiResult<UpsertResponse>> {
    return this.request<UpsertResponse>('/v1/upsert/batch', {
      method: 'POST',
      body: JSON.stringify(request),
    });
  }

  // ----- Info Endpoints -----

  async getModelInfo(): Promise<ApiResult<ModelInfo>> {
    return this.request<ModelInfo>('/v1/model');
  }

  async getIndexInfo(): Promise<ApiResult<IndexInfo>> {
    return this.request<IndexInfo>('/v1/index');
  }
}

// Export singleton instance
export const api = new ApiClient();

// Export class for custom instances
export { ApiClient };
