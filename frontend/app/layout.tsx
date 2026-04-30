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
      <body>
        {children}
      </body>
    </html>
  );
}
