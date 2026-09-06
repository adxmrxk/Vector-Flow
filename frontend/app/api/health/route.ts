import { NextResponse } from 'next/server';

// The next.config.js rewrite that used to serve this path is gated on
// NODE_ENV === 'development', so it does not exist in a production build.
// This route handler makes /api/health work in every environment.

export const dynamic = 'force-dynamic';

const GATEWAY_URL =
  process.env.GATEWAY_INTERNAL_URL ||
  process.env.NEXT_PUBLIC_API_URL ||
  'http://localhost:8080';

export async function GET() {
  try {
    const response = await fetch(`${GATEWAY_URL}/health`, {
      cache: 'no-store',
      signal: AbortSignal.timeout(5000),
    });

    const body = await response.json();
    return NextResponse.json(body, { status: response.status });
  } catch (error) {
    return NextResponse.json(
      {
        status: 'offline',
        error: 'GatewayUnreachable',
        message: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 503 }
    );
  }
}
