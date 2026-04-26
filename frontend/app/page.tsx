'use client';

import { useState, useCallback } from 'react';
import { Search, Loader2, AlertCircle, Sparkles } from 'lucide-react';
import { api } from '@/lib/api';
import type { SearchResult, SearchState } from '@/lib/types';

export default function HomePage() {
  const [state, setState] = useState<SearchState>({
    query: '',
    results: [],
    isLoading: false,
    error: null,
    latencyMs: null,
  });

  const handleSearch = useCallback(async (e: React.FormEvent) => {
    e.preventDefault();

    if (!state.query.trim()) return;

    setState((prev) => ({ ...prev, isLoading: true, error: null }));

    const result = await api.search({
      query: state.query,
      topK: 10,
      includeMetadata: true,
    });

    if (result.success) {
      setState((prev) => ({
        ...prev,
        results: result.data.results,
        latencyMs: result.data.latencyMs,
        isLoading: false,
      }));
    } else {
      setState((prev) => ({
        ...prev,
        error: result.error.message,
        isLoading: false,
      }));
    }
  }, [state.query]);

  return (
    <div className="container mx-auto px-4 py-12">
      {/* Hero Section */}
      <div className="text-center mb-12">
        <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-primary-100 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300 text-sm mb-4">
          <Sparkles className="w-4 h-4" />
          <span>Powered by AI</span>
        </div>
        <h1 className="text-4xl md:text-5xl font-bold mb-4">
          Semantic Search
        </h1>
        <p className="text-lg text-surface-600 dark:text-surface-400 max-w-2xl mx-auto">
          Find information based on meaning, not just keywords. Our AI understands
          the context and intent behind your queries.
        </p>
      </div>

      {/* Search Form */}
      <form onSubmit={handleSearch} className="max-w-3xl mx-auto mb-8">
        <div className="relative">
          <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-surface-400" />
          <input
            type="text"
            value={state.query}
            onChange={(e) =>
              setState((prev) => ({ ...prev, query: e.target.value }))
            }
            placeholder="Ask a question or describe what you're looking for..."
            className="w-full pl-12 pr-24 py-4 text-lg rounded-2xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 transition-all"
            disabled={state.isLoading}
          />
          <button
            type="submit"
            disabled={state.isLoading || !state.query.trim()}
            className="absolute right-2 top-1/2 -translate-y-1/2 px-6 py-2 rounded-xl bg-primary-600 hover:bg-primary-700 text-white font-medium disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            {state.isLoading ? (
              <Loader2 className="w-5 h-5 animate-spin" />
            ) : (
              'Search'
            )}
          </button>
        </div>
      </form>

      {/* Error Message */}
      {state.error && (
        <div className="max-w-3xl mx-auto mb-8 p-4 rounded-xl bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 flex items-center gap-3 text-red-700 dark:text-red-300">
          <AlertCircle className="w-5 h-5 flex-shrink-0" />
          <p>{state.error}</p>
        </div>
      )}

      {/* Results */}
      {state.results.length > 0 && (
        <div className="max-w-3xl mx-auto">
          <div className="flex items-center justify-between mb-4">
            <p className="text-sm text-surface-500">
              Found {state.results.length} results
            </p>
            {state.latencyMs && (
              <p className="text-sm text-surface-500">
                {state.latencyMs.toFixed(0)}ms
              </p>
            )}
          </div>

          <div className="space-y-4">
            {state.results.map((result, index) => (
              <ResultCard key={result.id} result={result} rank={index + 1} />
            ))}
          </div>
        </div>
      )}

      {/* Empty State */}
      {!state.isLoading && state.results.length === 0 && !state.error && (
        <div className="text-center py-12">
          <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-surface-100 dark:bg-surface-800 flex items-center justify-center">
            <Search className="w-8 h-8 text-surface-400" />
          </div>
          <p className="text-surface-500">
            Enter a query above to search
          </p>
        </div>
      )}
    </div>
  );
}

function ResultCard({ result, rank }: { result: SearchResult; rank: number }) {
  const relevancePercent = Math.round(result.score * 100);

  return (
    <div className="p-6 rounded-xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 hover:border-primary-300 dark:hover:border-primary-700 transition-colors animate-slide-up">
      <div className="flex items-start gap-4">
        <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary-100 dark:bg-primary-900/30 flex items-center justify-center text-sm font-medium text-primary-700 dark:text-primary-300">
          {rank}
        </div>

        <div className="flex-1 min-w-0">
          <div className="flex items-center justify-between mb-2">
            <h3 className="font-semibold text-lg truncate">{result.id}</h3>
            <span
              className={`px-2 py-1 rounded-full text-xs font-medium ${
                relevancePercent >= 80
                  ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300'
                  : relevancePercent >= 60
                  ? 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-300'
                  : 'bg-surface-100 text-surface-600 dark:bg-surface-700 dark:text-surface-300'
              }`}
            >
              {relevancePercent}% match
            </span>
          </div>

          {result.metadata && (
            <div className="flex flex-wrap gap-2 mt-3">
              {Object.entries(result.metadata).map(([key, value]) => (
                <span
                  key={key}
                  className="inline-flex items-center gap-1 px-2 py-1 rounded-md bg-surface-100 dark:bg-surface-700 text-xs"
                >
                  <span className="text-surface-500">{key}:</span>
                  <span className="font-medium">{String(value)}</span>
                </span>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
