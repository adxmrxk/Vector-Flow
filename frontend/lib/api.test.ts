import { api } from './api';

describe('ApiClient', () => {
  const mockFetch = jest.fn();

  beforeEach(() => {
    mockFetch.mockReset();
    global.fetch = mockFetch as unknown as typeof fetch;
  });

  function jsonResponse(body: unknown, ok = true, status = 200) {
    return Promise.resolve({
      ok,
      status,
      json: () => Promise.resolve(body),
    });
  }

  it('sends snake_case keys the Go gateway actually binds', async () => {
    mockFetch.mockReturnValue(jsonResponse({ results: [], query: 'q' }));

    await api.search({ query: 'electric car', topK: 5 });

    expect(mockFetch).toHaveBeenCalledTimes(1);
    const [url, init] = mockFetch.mock.calls[0];
    expect(url).toContain('/v1/search');

    const body = JSON.parse(init.body);
    expect(body).toMatchObject({
      query: 'electric car',
      top_k: 5,
      include_metadata: true,
    });
    // camelCase variants would be silently ignored by the gateway's binding.
    expect(body).not.toHaveProperty('topK');
    expect(body).not.toHaveProperty('includeMetadata');
  });

  it('defaults top_k to 10 when unspecified', async () => {
    mockFetch.mockReturnValue(jsonResponse({ results: [], query: 'q' }));
    await api.search({ query: 'q' });
    expect(JSON.parse(mockFetch.mock.calls[0][1].body).top_k).toBe(10);
  });

  it('returns success:true with the parsed payload on 200', async () => {
    mockFetch.mockReturnValue(
      jsonResponse({ embeddings: [[0.1, 0.2]], dimension: 384, model: 'm' })
    );

    const result = await api.createEmbeddings({ texts: ['hi'] });

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.dimension).toBe(384);
    }
  });

  it('returns success:false carrying the error body on a non-2xx', async () => {
    mockFetch.mockReturnValue(
      jsonResponse({ error: 'InternalError', message: 'Search failed' }, false, 500)
    );

    const result = await api.search({ query: 'q' });

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.error).toBe('InternalError');
    }
  });

  it('surfaces a NetworkError instead of throwing when fetch rejects', async () => {
    mockFetch.mockRejectedValue(new Error('connection refused'));

    const result = await api.health();

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.error).toBe('NetworkError');
      expect(result.error.message).toBe('connection refused');
    }
  });

  it('requests /v1/index, the route the gateway now registers', async () => {
    mockFetch.mockReturnValue(
      jsonResponse({ dimension: 384, total_vector_count: 7, namespaces: {} })
    );

    const result = await api.getIndexInfo();

    expect(mockFetch.mock.calls[0][0]).toContain('/v1/index');
    expect(result.success).toBe(true);
  });
});
