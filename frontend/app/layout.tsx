import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'VectorFlow - Semantic Search',
  description: 'Enterprise semantic search powered by AI',
  keywords: ['semantic search', 'AI', 'machine learning', 'embeddings'],
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-surface-50 dark:bg-surface-900 text-surface-900 dark:text-surface-50 antialiased">
        <div className="flex flex-col min-h-screen">
          {/* Header */}
          <header className="sticky top-0 z-50 w-full border-b border-surface-200 dark:border-surface-700 bg-white/80 dark:bg-surface-900/80 backdrop-blur-sm">
            <div className="container mx-auto px-4 h-16 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-lg bg-primary-600 flex items-center justify-center">
                  <svg
                    className="w-5 h-5 text-white"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
                    />
                  </svg>
                </div>
                <span className="text-xl font-semibold">VectorFlow</span>
              </div>

              <nav className="hidden md:flex items-center gap-6">
                <a
                  href="/"
                  className="text-sm font-medium hover:text-primary-600 transition-colors"
                >
                  Search
                </a>
                <a
                  href="/docs"
                  className="text-sm font-medium text-surface-500 hover:text-primary-600 transition-colors"
                >
                  Docs
                </a>
                <a
                  href="/status"
                  className="text-sm font-medium text-surface-500 hover:text-primary-600 transition-colors"
                >
                  Status
                </a>
              </nav>
            </div>
          </header>

          {/* Main Content */}
          <main className="flex-1">{children}</main>

          {/* Footer */}
          <footer className="border-t border-surface-200 dark:border-surface-700 py-6">
            <div className="container mx-auto px-4 text-center text-sm text-surface-500">
              <p>VectorFlow - Enterprise Semantic Search Platform</p>
            </div>
          </footer>
        </div>
      </body>
    </html>
  );
}
