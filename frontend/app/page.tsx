'use client';

import { useState, useCallback, useEffect } from 'react';
import {
  Search,
  Loader2,
  AlertCircle,
  Clock,
  X,
  ChevronDown,
  Activity,
  Database,
  Cpu,
  Layers,
  TrendingUp
} from 'lucide-react';
import { api } from '@/lib/api';
import type { SearchResult, SearchState } from '@/lib/types';

const EXAMPLE_QUERIES = [
  'How does machine learning work?',
  'Best practices for API design',
  'Introduction to neural networks',
  'Data preprocessing techniques',
];

export default function HomePage() {
  const [state, setState] = useState<SearchState>({
    query: '',
    results: [],
    isLoading: false,
    error: null,
    latencyMs: null,
  });

  const [topK, setTopK] = useState(10);
  const [threshold, setThreshold] = useState(0.5);
  const [recentSearches, setRecentSearches] = useState<string[]>([]);
  const [systemStatus, setSystemStatus] = useState<'online' | 'offline' | 'checking'>('checking');

  useEffect(() => {
    const saved = localStorage.getItem('recentSearches');
    if (saved) setRecentSearches(JSON.parse(saved));
    checkStatus();
  }, []);

  const checkStatus = async () => {
    try {
      const response = await fetch('/api/health');
      setSystemStatus(response.ok ? 'online' : 'offline');
    } catch {
      setSystemStatus('offline');
    }
  };

  const saveSearch = (query: string) => {
    const updated = [query, ...recentSearches.filter(s => s !== query)].slice(0, 5);
    setRecentSearches(updated);
    localStorage.setItem('recentSearches', JSON.stringify(updated));
  };

  const handleSearch = useCallback(async (searchQuery?: string) => {
    const query = searchQuery || state.query;
    if (!query.trim()) return;

    setState((prev) => ({ ...prev, query, isLoading: true, error: null }));
    saveSearch(query);

    const result = await api.search({
      query,
      topK,
      includeMetadata: true,
    });

    if (result.success) {
      const filtered = result.data.results.filter((r: SearchResult) => r.score >= threshold);
      setState((prev) => ({
        ...prev,
        results: filtered,
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
  }, [state.query, topK, threshold]);

  const clearSearch = () => {
    setState({
      query: '',
      results: [],
      isLoading: false,
      error: null,
      latencyMs: null,
    });
  };

  return (
    <div className="min-h-screen bg-gray-100">
      {/* Header */}
      <header className="bg-gray-900 border-b border-gray-800">
        <div className="max-w-7xl mx-auto px-6">
          <div className="flex items-center justify-between h-14">
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-md bg-gradient-to-br from-green-400 to-green-600 flex items-center justify-center shadow-lg shadow-green-500/20">
                <Layers className="w-4 h-4 text-white" />
              </div>
              <span className="text-base font-semibold text-white">VectorFlow</span>
            </div>

            <div className="flex items-center gap-6">
              <nav className="flex items-center gap-5">
                <a href="#" className="text-sm text-gray-300 hover:text-white transition-colors">Docs</a>
                <a href="#" className="text-sm text-gray-300 hover:text-white transition-colors">API</a>
              </nav>
              <div className="h-4 w-px bg-gray-700"></div>
              <div className="flex items-center gap-2">
                <span className={`w-2 h-2 rounded-full ${
                  systemStatus === 'online' ? 'bg-green-400 shadow-sm shadow-green-400/50' :
                  systemStatus === 'offline' ? 'bg-red-400' : 'bg-yellow-400 animate-pulse'
                }`} />
                <span className="text-sm text-gray-400">
                  {systemStatus === 'checking' ? 'Checking' : systemStatus === 'online' ? 'Online' : 'Offline'}
                </span>
              </div>
            </div>
          </div>
        </div>
      </header>

      <div className="max-w-7xl mx-auto px-6 py-6">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">

          {/* Sidebar */}
          <aside className="lg:col-span-3 space-y-4">
            {/* Stats Card */}
            <div className="bg-white rounded-lg border border-gray-200 shadow-sm overflow-hidden">
              <div className="px-4 py-3 bg-gray-50 border-b border-gray-200">
                <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Statistics</h3>
              </div>
              <div className="p-4 space-y-3">
                <div className="flex items-center justify-between py-2 px-3 bg-gray-50 rounded-md">
                  <div className="flex items-center gap-2">
                    <Activity className="w-4 h-4 text-green-500" />
                    <span className="text-sm text-gray-600">Latency</span>
                  </div>
                  <span className="text-sm font-semibold text-gray-800">
                    {state.latencyMs ? `${state.latencyMs.toFixed(0)}ms` : '--'}
                  </span>
                </div>
                <div className="flex items-center justify-between py-2 px-3 bg-gray-50 rounded-md">
                  <div className="flex items-center gap-2">
                    <Database className="w-4 h-4 text-green-600" />
                    <span className="text-sm text-gray-600">Results</span>
                  </div>
                  <span className="text-sm font-semibold text-gray-800">{state.results.length}</span>
                </div>
                <div className="flex items-center justify-between py-2 px-3 bg-gray-50 rounded-md">
                  <div className="flex items-center gap-2">
                    <TrendingUp className="w-4 h-4 text-green-700" />
                    <span className="text-sm text-gray-600">Top K</span>
                  </div>
                  <span className="text-sm font-semibold text-gray-800">{topK}</span>
                </div>
              </div>
            </div>

            {/* Settings Card */}
            <div className="bg-white rounded-lg border border-gray-200 shadow-sm overflow-hidden">
              <div className="px-4 py-3 bg-gray-50 border-b border-gray-200">
                <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Settings</h3>
              </div>
              <div className="p-4 space-y-5">
                <div>
                  <div className="flex items-center justify-between mb-2">
                    <label className="text-sm text-gray-600">Results Limit</label>
                    <span className="text-xs font-semibold text-green-600 bg-green-50 px-2 py-0.5 rounded">{topK}</span>
                  </div>
                  <input
                    type="range"
                    min="1"
                    max="50"
                    value={topK}
                    onChange={(e) => setTopK(Number(e.target.value))}
                    className="w-full h-1.5 bg-gray-200 rounded-full appearance-none cursor-pointer accent-green-500"
                  />
                  <div className="flex justify-between mt-1">
                    <span className="text-xs text-gray-400">1</span>
                    <span className="text-xs text-gray-400">50</span>
                  </div>
                </div>
                <div>
                  <div className="flex items-center justify-between mb-2">
                    <label className="text-sm text-gray-600">Min Score</label>
                    <span className="text-xs font-semibold text-green-600 bg-green-50 px-2 py-0.5 rounded">{(threshold * 100).toFixed(0)}%</span>
                  </div>
                  <input
                    type="range"
                    min="0"
                    max="100"
                    value={threshold * 100}
                    onChange={(e) => setThreshold(Number(e.target.value) / 100)}
                    className="w-full h-1.5 bg-gray-200 rounded-full appearance-none cursor-pointer accent-green-500"
                  />
                  <div className="flex justify-between mt-1">
                    <span className="text-xs text-gray-400">0%</span>
                    <span className="text-xs text-gray-400">100%</span>
                  </div>
                </div>
              </div>
            </div>

            {/* Recent Searches */}
            {recentSearches.length > 0 && (
              <div className="bg-white rounded-lg border border-gray-200 shadow-sm overflow-hidden">
                <div className="px-4 py-3 bg-gray-50 border-b border-gray-200">
                  <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Recent</h3>
                </div>
                <div className="p-2">
                  {recentSearches.map((search, i) => (
                    <button
                      key={i}
                      onClick={() => {
                        setState(prev => ({ ...prev, query: search }));
                        handleSearch(search);
                      }}
                      className="w-full flex items-center gap-2 px-3 py-2 text-sm text-gray-600 hover:bg-gray-100 hover:text-gray-900 rounded-md transition-colors text-left group"
                    >
                      <Clock className="w-3.5 h-3.5 text-gray-400 group-hover:text-green-500" />
                      <span className="truncate">{search}</span>
                    </button>
                  ))}
                </div>
              </div>
            )}
          </aside>

          {/* Main Content */}
          <main className="lg:col-span-9 space-y-4">
            {/* Search Box */}
            <div className="bg-white rounded-lg border border-gray-200 shadow-sm p-5">
              <form onSubmit={(e) => { e.preventDefault(); handleSearch(); }}>
                <div className="flex gap-3">
                  <div className="relative flex-1">
                    <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
                    <input
                      type="text"
                      value={state.query}
                      onChange={(e) => setState((prev) => ({ ...prev, query: e.target.value }))}
                      placeholder="Search for anything..."
                      className="w-full pl-12 pr-10 py-3 bg-gray-50 border border-gray-300 rounded-lg text-gray-900 placeholder-gray-500 focus:outline-none focus:bg-white focus:border-green-500 focus:ring-2 focus:ring-green-100 transition-all"
                      disabled={state.isLoading}
                    />
                    {state.query && (
                      <button
                        type="button"
                        onClick={clearSearch}
                        className="absolute right-3 top-1/2 -translate-y-1/2 p-1.5 text-gray-400 hover:text-gray-600 hover:bg-gray-200 rounded-md transition-colors"
                      >
                        <X className="w-4 h-4" />
                      </button>
                    )}
                  </div>
                  <button
                    type="submit"
                    disabled={state.isLoading || !state.query.trim()}
                    className="px-5 py-3 bg-gradient-to-r from-green-500 to-green-600 hover:from-green-600 hover:to-green-700 disabled:from-gray-300 disabled:to-gray-400 text-white font-medium rounded-lg transition-all shadow-sm hover:shadow-md disabled:shadow-none flex items-center gap-2"
                  >
                    {state.isLoading ? (
                      <Loader2 className="w-5 h-5 animate-spin" />
                    ) : (
                      <>
                        <Search className="w-4 h-4" />
                        <span>Search</span>
                      </>
                    )}
                  </button>
                </div>
              </form>

              {/* Example Queries */}
              {!state.query && state.results.length === 0 && (
                <div className="mt-4 pt-4 border-t border-gray-100">
                  <p className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-3">Try an example</p>
                  <div className="flex flex-wrap gap-2">
                    {EXAMPLE_QUERIES.map((example, i) => (
                      <button
                        key={i}
                        onClick={() => {
                          setState(prev => ({ ...prev, query: example }));
                          handleSearch(example);
                        }}
                        className="px-3 py-1.5 text-sm text-gray-700 bg-gray-100 hover:bg-green-50 hover:text-green-700 border border-gray-200 hover:border-green-200 rounded-md transition-colors"
                      >
                        {example}
                      </button>
                    ))}
                  </div>
                </div>
              )}
            </div>

            {/* Error */}
            {state.error && (
              <div className="bg-red-50 border border-red-200 rounded-lg p-4 flex items-start gap-3">
                <div className="w-8 h-8 rounded-full bg-red-100 flex items-center justify-center flex-shrink-0">
                  <AlertCircle className="w-4 h-4 text-red-600" />
                </div>
                <div>
                  <p className="font-medium text-red-800">Search failed</p>
                  <p className="text-sm text-red-600 mt-0.5">{state.error}</p>
                </div>
              </div>
            )}

            {/* Results */}
            {state.results.length > 0 && (
              <div className="space-y-3">
                <div className="flex items-center justify-between px-1">
                  <p className="text-sm text-gray-600">
                    Found <span className="font-semibold text-gray-900">{state.results.length}</span> results
                  </p>
                  {state.latencyMs && (
                    <span className="text-xs text-gray-500 bg-gray-100 px-2 py-1 rounded">{state.latencyMs.toFixed(0)}ms</span>
                  )}
                </div>

                <div className="space-y-3">
                  {state.results.map((result, index) => (
                    <ResultCard key={result.id} result={result} rank={index + 1} />
                  ))}
                </div>
              </div>
            )}

            {/* Empty State */}
            {!state.isLoading && state.results.length === 0 && !state.error && state.query && (
              <div className="bg-white rounded-lg border border-gray-200 shadow-sm p-10 text-center">
                <div className="w-12 h-12 mx-auto mb-3 rounded-lg bg-gray-100 flex items-center justify-center">
                  <Search className="w-5 h-5 text-gray-400" />
                </div>
                <p className="text-gray-800 font-medium">No results found</p>
                <p className="text-sm text-gray-500 mt-1">Try adjusting your search or filters</p>
              </div>
            )}

            {/* Initial State */}
            {!state.query && state.results.length === 0 && !state.error && (
              <div className="bg-gradient-to-br from-gray-50 to-gray-100 rounded-lg border border-gray-200 p-10 text-center">
                <div className="w-14 h-14 mx-auto mb-4 rounded-xl bg-gradient-to-br from-green-400 to-green-600 flex items-center justify-center shadow-lg shadow-green-200">
                  <Database className="w-6 h-6 text-white" />
                </div>
                <p className="text-gray-800 font-semibold text-lg">Ready to search</p>
                <p className="text-sm text-gray-500 mt-1">Enter a query or select an example above</p>
              </div>
            )}
          </main>
        </div>
      </div>
    </div>
  );
}

function ResultCard({ result, rank }: { result: SearchResult; rank: number }) {
  const relevancePercent = Math.round(result.score * 100);
  const [expanded, setExpanded] = useState(false);

  const getScoreColor = () => {
    if (relevancePercent >= 80) return { bg: 'bg-green-500', text: 'text-green-700', light: 'bg-green-50' };
    if (relevancePercent >= 60) return { bg: 'bg-green-400', text: 'text-green-600', light: 'bg-green-50' };
    if (relevancePercent >= 40) return { bg: 'bg-gray-400', text: 'text-gray-600', light: 'bg-gray-50' };
    return { bg: 'bg-gray-300', text: 'text-gray-500', light: 'bg-gray-50' };
  };

  const colors = getScoreColor();

  return (
    <div className="bg-white rounded-lg border border-gray-200 hover:border-green-300 shadow-sm hover:shadow transition-all overflow-hidden">
      <div className="p-4">
        <div className="flex items-start gap-4">
          <div className="flex-shrink-0 w-9 h-9 rounded-md bg-gray-800 flex items-center justify-center text-sm font-semibold text-white">
            {rank}
          </div>

          <div className="flex-1 min-w-0">
            <div className="flex items-center justify-between gap-4">
              <h3 className="font-semibold text-gray-900 truncate">{result.id}</h3>
              <div className="flex items-center gap-2 flex-shrink-0">
                <div className="w-24 h-2 rounded-full bg-gray-200 overflow-hidden">
                  <div
                    className={`h-full rounded-full ${colors.bg} transition-all`}
                    style={{ width: `${relevancePercent}%` }}
                  />
                </div>
                <span className={`text-sm font-semibold ${colors.text} ${colors.light} px-2 py-0.5 rounded`}>
                  {relevancePercent}%
                </span>
              </div>
            </div>

            {result.metadata && Object.keys(result.metadata).length > 0 && (
              <>
                <button
                  onClick={() => setExpanded(!expanded)}
                  className="mt-2 flex items-center gap-1 text-xs font-medium text-gray-500 hover:text-green-600 transition-colors"
                >
                  <ChevronDown className={`w-3.5 h-3.5 transition-transform ${expanded ? 'rotate-180' : ''}`} />
                  {expanded ? 'Hide' : 'View'} metadata
                </button>

                {expanded && (
                  <div className="mt-3 p-3 bg-gray-50 border border-gray-100 rounded-md">
                    <div className="grid gap-2">
                      {Object.entries(result.metadata).map(([key, value]) => (
                        <div key={key} className="flex items-start gap-3 text-sm">
                          <span className="text-gray-500 font-medium min-w-[100px]">{key}</span>
                          <span className="text-gray-700 break-all">{String(value)}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
