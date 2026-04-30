from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

import click
from dotenv import load_dotenv
from rich.console import Console
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.table import Table

from . import __version__
from .client import VectorFlowClient

load_dotenv()

console = Console()
error_console = Console(stderr=True)


def get_client(gateway_url: str | None = None) -> VectorFlowClient:
    """Create a VectorFlow client instance."""
    return VectorFlowClient(gateway_url=gateway_url)


@click.group()
@click.version_option(version=__version__, prog_name="vectorflow")
@click.option(
    "--gateway-url",
    envvar="VECTORFLOW_GATEWAY_URL",
    default="http://localhost:8080",
    help="VectorFlow gateway URL",
)
@click.pass_context
def cli(ctx: click.Context, gateway_url: str) -> None:
    """VectorFlow CLI - Enterprise Semantic Search Platform

    A command-line tool for interacting with VectorFlow services.
    Perform searches, batch-process data, and check system health.

    Examples:

        \b
        # Search for documents
        vectorflow search "machine learning concepts"

        \b
        # Check system health
        vectorflow health

        \b
        # Batch upsert from JSON file
        vectorflow batch-upsert data.json
    """
    ctx.ensure_object(dict)
    ctx.obj["gateway_url"] = gateway_url


@cli.command()
@click.pass_context
def health(ctx: click.Context) -> None:
    """Check health of all VectorFlow services.

    Displays the status of the gateway and all downstream services
    including the inference service and worker.
    """
    gateway_url = ctx.obj["gateway_url"]

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
        transient=True,
    ) as progress:
        progress.add_task("Checking service health...", total=None)

        try:
            with get_client(gateway_url) as client:
                statuses = client.check_all_services()
        except Exception as e:
            error_console.print(f"[red]Error connecting to gateway:[/red] {e}")
            sys.exit(1)

    # Build status table
    table = Table(title="VectorFlow Service Health", show_header=True)
    table.add_column("Service", style="cyan")
    table.add_column("Status", style="bold")
    table.add_column("Details")

    for status in statuses:
        status_color = "green" if status.status in ("healthy", "ready") else "red"
        details = ""
        if status.details:
            if "version" in status.details:
                details = f"v{status.details['version']}"
            elif "error" in status.details:
                details = str(status.details["error"])[:50]

        table.add_row(
            status.service,
            f"[{status_color}]{status.status}[/{status_color}]",
            details,
        )

    console.print(table)

    # Exit with error if any service is unhealthy
    if any(s.status not in ("healthy", "ready") for s in statuses):
        sys.exit(1)


@cli.command()
@click.pass_context
def status(ctx: click.Context) -> None:
    """Show detailed system status including model and index info.

    Displays comprehensive information about the currently loaded model,
    vector index statistics, and service configuration.
    """
    gateway_url = ctx.obj["gateway_url"]

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
        transient=True,
    ) as progress:
        progress.add_task("Fetching system status...", total=None)

        try:
            with get_client(gateway_url) as client:
                health_status = client.health()
                model_info = client.model_info()
                index_stats = client.index_stats()
        except Exception as e:
            error_console.print(f"[red]Error:[/red] {e}")
            sys.exit(1)

    # Model info panel
    model_text = (
        f"[bold]Model:[/bold] {model_info.name}\n"
        f"[bold]Dimension:[/bold] {model_info.dimension}\n"
        f"[bold]Max Sequence Length:[/bold] {model_info.max_sequence_length}\n"
        f"[bold]Device:[/bold] {model_info.device}"
    )
    console.print(Panel(model_text, title="Model Information", border_style="blue"))

    # Index stats panel
    index_text = (
        f"[bold]Total Vectors:[/bold] {index_stats.total_vectors:,}\n"
        f"[bold]Dimension:[/bold] {index_stats.dimension}"
    )
    if index_stats.namespaces:
        ns_list = ", ".join(f"{k}: {v:,}" for k, v in index_stats.namespaces.items())
        index_text += f"\n[bold]Namespaces:[/bold] {ns_list}"
    console.print(Panel(index_text, title="Index Statistics", border_style="green"))

    # Gateway info
    gateway_text = f"[bold]URL:[/bold] {gateway_url}\n[bold]Status:[/bold] {health_status.status}"
    if health_status.version:
        gateway_text += f"\n[bold]Version:[/bold] {health_status.version}"
    console.print(Panel(gateway_text, title="Gateway", border_style="cyan"))


@cli.command()
@click.argument("query")
@click.option("-k", "--top-k", default=10, help="Number of results to return")
@click.option("-n", "--namespace", default=None, help="Namespace to search in")
@click.option("-t", "--threshold", default=0.0, type=float, help="Minimum score threshold")
@click.option("--json", "output_json", is_flag=True, help="Output results as JSON")
@click.pass_context
def search(
    ctx: click.Context,
    query: str,
    top_k: int,
    namespace: str | None,
    threshold: float,
    output_json: bool,
) -> None:
    """Perform semantic search.

    QUERY is the search text to find semantically similar documents.

    Examples:

        \b
        vectorflow search "how does machine learning work"
        vectorflow search "API design patterns" -k 5
        vectorflow search "neural networks" --namespace articles
    """
    gateway_url = ctx.obj["gateway_url"]

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
        transient=True,
    ) as progress:
        progress.add_task("Searching...", total=None)

        try:
            with get_client(gateway_url) as client:
                response = client.search(
                    query=query,
                    top_k=top_k,
                    namespace=namespace,
                )
        except Exception as e:
            error_console.print(f"[red]Search failed:[/red] {e}")
            sys.exit(1)

    # Filter by threshold
    results = [r for r in response.results if r.score >= threshold]

    if output_json:
        output = {
            "query": query,
            "latencyMs": response.latency_ms,
            "results": [
                {"id": r.id, "score": r.score, "metadata": r.metadata}
                for r in results
            ],
        }
        console.print_json(json.dumps(output))
        return

    # Pretty print results
    if not results:
        console.print("[yellow]No results found.[/yellow]")
        return

    console.print(f"\n[dim]Found {len(results)} results in {response.latency_ms:.0f}ms[/dim]\n")

    for i, result in enumerate(results, 1):
        score_pct = result.score * 100
        score_color = "green" if score_pct >= 70 else "yellow" if score_pct >= 50 else "red"

        console.print(f"[bold]{i}.[/bold] [cyan]{result.id}[/cyan]")
        console.print(f"   Score: [{score_color}]{score_pct:.1f}%[/{score_color}]")

        if result.metadata:
            meta_str = ", ".join(f"{k}={v}" for k, v in list(result.metadata.items())[:3])
            console.print(f"   [dim]{meta_str}[/dim]")
        console.print()


@cli.command()
@click.argument("id")
@click.argument("text")
@click.option("-m", "--metadata", default=None, help="JSON metadata string")
@click.option("-n", "--namespace", default=None, help="Namespace for the vector")
@click.pass_context
def upsert(
    ctx: click.Context,
    id: str,
    text: str,
    metadata: str | None,
    namespace: str | None,
) -> None:
    """Upsert a single document.

    ID is the unique identifier for the document.
    TEXT is the content to embed and store.

    Examples:

        \b
        vectorflow upsert doc-1 "Machine learning is a subset of AI"
        vectorflow upsert doc-2 "Deep learning uses neural networks" -m '{"category": "AI"}'
    """
    gateway_url = ctx.obj["gateway_url"]

    meta_dict: dict[str, Any] | None = None
    if metadata:
        try:
            meta_dict = json.loads(metadata)
        except json.JSONDecodeError as e:
            error_console.print(f"[red]Invalid metadata JSON:[/red] {e}")
            sys.exit(1)

    try:
        with get_client(gateway_url) as client:
            result_id = client.upsert(
                id=id,
                text=text,
                metadata=meta_dict,
                namespace=namespace,
            )
        console.print(f"[green]Successfully upserted:[/green] {result_id}")
    except Exception as e:
        error_console.print(f"[red]Upsert failed:[/red] {e}")
        sys.exit(1)


@cli.command("batch-upsert")
@click.argument("file", type=click.Path(exists=True, path_type=Path))
@click.option("-n", "--namespace", default=None, help="Namespace for vectors")
@click.option("--batch-size", default=100, help="Vectors per batch request")
@click.option("--dry-run", is_flag=True, help="Validate file without upserting")
@click.pass_context
def batch_upsert(
    ctx: click.Context,
    file: Path,
    namespace: str | None,
    batch_size: int,
    dry_run: bool,
) -> None:
    """Batch upsert documents from a JSON file.

    FILE should be a JSON file containing an array of objects with:
    - id: unique identifier (required)
    - text: content to embed (required)
    - metadata: optional metadata object

    Example JSON format:

        \b
        [
          {"id": "doc-1", "text": "First document", "metadata": {"type": "article"}},
          {"id": "doc-2", "text": "Second document"}
        ]

    Examples:

        \b
        vectorflow batch-upsert documents.json
        vectorflow batch-upsert data.json --namespace articles --batch-size 50
        vectorflow batch-upsert test.json --dry-run
    """
    gateway_url = ctx.obj["gateway_url"]

    # Load and validate file
    try:
        with open(file) as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        error_console.print(f"[red]Invalid JSON file:[/red] {e}")
        sys.exit(1)

    if not isinstance(data, list):
        error_console.print("[red]JSON file must contain an array of objects[/red]")
        sys.exit(1)

    # Validate entries
    valid_vectors: list[dict[str, Any]] = []
    errors: list[str] = []

    for i, entry in enumerate(data):
        if not isinstance(entry, dict):
            errors.append(f"Entry {i}: not an object")
            continue
        if "id" not in entry:
            errors.append(f"Entry {i}: missing 'id' field")
            continue
        if "text" not in entry:
            errors.append(f"Entry {i}: missing 'text' field")
            continue

        valid_vectors.append({
            "id": entry["id"],
            "text": entry["text"],
            "metadata": entry.get("metadata"),
        })

    if errors:
        error_console.print("[red]Validation errors:[/red]")
        for err in errors[:10]:
            error_console.print(f"  - {err}")
        if len(errors) > 10:
            error_console.print(f"  ... and {len(errors) - 10} more errors")
        sys.exit(1)

    console.print(f"[dim]Found {len(valid_vectors)} valid documents[/dim]")

    if dry_run:
        console.print("[yellow]Dry run - no data uploaded[/yellow]")
        return

    # Batch upload
    total_upserted = 0
    batches = [valid_vectors[i:i + batch_size] for i in range(0, len(valid_vectors), batch_size)]

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
    ) as progress:
        task = progress.add_task(
            f"Uploading {len(valid_vectors)} documents...",
            total=len(batches),
        )

        try:
            with get_client(gateway_url) as client:
                for batch in batches:
                    count = client.upsert_batch(vectors=batch, namespace=namespace)
                    total_upserted += count
                    progress.advance(task)
        except Exception as e:
            error_console.print(f"\n[red]Batch upsert failed:[/red] {e}")
            error_console.print(f"[yellow]Uploaded {total_upserted} documents before failure[/yellow]")
            sys.exit(1)

    console.print(f"[green]Successfully upserted {total_upserted} documents[/green]")


@cli.command()
@click.argument("texts", nargs=-1, required=True)
@click.option("--json", "output_json", is_flag=True, help="Output as JSON")
@click.pass_context
def embed(ctx: click.Context, texts: tuple[str, ...], output_json: bool) -> None:
    """Generate embeddings for text.

    TEXTS are one or more strings to embed.

    Examples:

        \b
        vectorflow embed "Hello world"
        vectorflow embed "First text" "Second text" --json
    """
    gateway_url = ctx.obj["gateway_url"]

    try:
        with get_client(gateway_url) as client:
            embeddings = client.embed(list(texts))
    except Exception as e:
        error_console.print(f"[red]Embedding failed:[/red] {e}")
        sys.exit(1)

    if output_json:
        output = {"texts": list(texts), "embeddings": embeddings}
        console.print_json(json.dumps(output))
        return

    for i, (text, emb) in enumerate(zip(texts, embeddings)):
        console.print(f"[bold]{i + 1}.[/bold] [cyan]{text[:50]}{'...' if len(text) > 50 else ''}[/cyan]")
        console.print(f"   Dimension: {len(emb)}")
        console.print(f"   Preview: [{emb[0]:.4f}, {emb[1]:.4f}, ..., {emb[-1]:.4f}]")
        console.print()


def main() -> None:
    """CLI entry point."""
    cli(obj={})


if __name__ == "__main__":
    main()
