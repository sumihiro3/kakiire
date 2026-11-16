#!/usr/bin/env python3
"""GitHub Releases のダウンロード数と、リポジトリの clone・閲覧数を取って記録する(docs/download-stats.md)。

    python3 scripts/download-stats.py <出力先のフォルダ>

出力先に次の4つを書く。同じ日に何度実行しても、その日の行を置き換えるだけ。
- assets.csv   日付・タグ・ファイル名・種類(app / cli)・その時点の累計ダウンロード数
- traffic.csv  日付・リポジトリ・clones / views・回数・人数(GitHub は 14 日分しか持たないので毎日写す)
- web.csv      日付・LP のパス・参照元・ページビュー・訪問数(Cloudflare Web Analytics。直近 7 日を毎回取り直す)
- summary.md   最新の累計と、1日前・7日前からの増え方、版ごとの数、直近 14 日の traffic と LP の訪問

GitHub への問い合わせは gh(認証済みのもの)を使う。traffic は push 権限が要る。
Cloudflare は出力先の cloudflare.json(account_tag・site_tag)と、キーチェーンの API トークン
(サービス名 kakiire-cloudflare-analytics)を使う。どちらかがなければ web.csv は書かず、ほかは続ける。
"""

from __future__ import annotations

import csv
import datetime as dt
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

REPO = "sumihiro3/kakiire"
TRAFFIC_REPOS = ["sumihiro3/kakiire", "sumihiro3/homebrew-tap"]
ASSET_FIELDS = ["date", "tag", "asset", "kind", "downloads"]
TRAFFIC_FIELDS = ["date", "repo", "metric", "count", "uniques"]
WEB_FIELDS = ["date", "path", "referer", "pageviews", "visits"]
WEB_DAYS = 7
KEYCHAIN_SERVICE = "kakiire-cloudflare-analytics"
GRAPHQL_URL = "https://api.cloudflare.com/client/v4/graphql"
WEB_QUERY = """
query ($accountTag: string!, $siteTag: string!, $since: Date!, $until: Date!) {
  viewer {
    accounts(filter: {accountTag: $accountTag}) {
      rumPageloadEventsAdaptiveGroups(
        limit: 5000
        filter: {siteTag: $siteTag, date_geq: $since, date_leq: $until, bot: 0}
      ) {
        count
        sum { visits }
        dimensions { date requestPath refererHost }
      }
    }
  }
}
"""


def gh_api(path: str) -> object:
    out = subprocess.run(
        ["gh", "api", "--paginate", "--slurp", path],
        check=True, capture_output=True, text=True,
    ).stdout
    pages = json.loads(out)
    if pages and isinstance(pages[0], list):
        return [item for page in pages for item in page]
    return pages[0] if pages else {}


def kind_of(asset: str) -> str:
    """ファイル名から、アプリと CLI のどちらの配布物かを決める(CLI は小文字の kakiire- で始まる)。"""
    return "cli" if asset.startswith("kakiire-") else "app"


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    tmp = path.with_suffix(".tmp")
    with tmp.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    tmp.replace(path)


def collect_assets(today: str) -> list[dict[str, str]]:
    rows = []
    for release in gh_api(f"repos/{REPO}/releases"):
        for a in release["assets"]:
            rows.append({
                "date": today, "tag": release["tag_name"], "asset": a["name"],
                "kind": kind_of(a["name"]), "downloads": str(a["download_count"]),
            })
    return rows


def collect_traffic() -> list[dict[str, str]]:
    rows = []
    for repo in TRAFFIC_REPOS:
        for metric in ("clones", "views"):
            data = gh_api(f"repos/{repo}/traffic/{metric}")
            for day in data.get(metric, []):
                rows.append({
                    "date": day["timestamp"][:10], "repo": repo, "metric": metric,
                    "count": str(day["count"]), "uniques": str(day["uniques"]),
                })
    return rows


def cloudflare_settings(out: Path) -> tuple[str, str, str] | None:
    """cloudflare.json とキーチェーンから (account_tag, site_tag, token) を読む。揃わなければ None。"""
    conf = out / "cloudflare.json"
    if not conf.exists():
        return None
    c = json.loads(conf.read_text())
    token = subprocess.run(
        ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
        capture_output=True, text=True,
    ).stdout.strip()
    if not (c.get("account_tag") and c.get("site_tag") and token):
        return None
    return c["account_tag"], c["site_tag"], token


def page_of(path: str) -> str:
    """LP のパスを、日本語版(ja)・英語版(en)・それ以外にまとめる。"""
    if path in ("/", "/index.html"):
        return "ja"
    if path in ("/en", "/en/", "/en/index.html"):
        return "en"
    return "other"


def collect_web(account_tag: str, site_tag: str, token: str, today: str) -> list[dict[str, str]]:
    since = (dt.date.fromisoformat(today) - dt.timedelta(days=WEB_DAYS - 1)).isoformat()
    body = json.dumps({"query": WEB_QUERY, "variables": {
        "accountTag": account_tag, "siteTag": site_tag, "since": since, "until": today,
    }}).encode()
    req = urllib.request.Request(GRAPHQL_URL, data=body, headers={
        "Authorization": f"Bearer {token}", "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req, timeout=30) as res:
        data = json.load(res)
    if data.get("errors"):
        raise RuntimeError(json.dumps(data["errors"], ensure_ascii=False))
    accounts = data["data"]["viewer"]["accounts"]
    groups = accounts[0]["rumPageloadEventsAdaptiveGroups"] if accounts else []
    rows = [{
        "date": g["dimensions"]["date"], "path": g["dimensions"]["requestPath"],
        "referer": g["dimensions"]["refererHost"] or "(direct)",
        "pageviews": str(g["count"]), "visits": str(g["sum"]["visits"]),
    } for g in groups]
    rows.sort(key=lambda r: (r["date"], r["path"], r["referer"]))
    return rows


def merge_web(old: list[dict[str, str]], fresh: list[dict[str, str]], today: str) -> list[dict[str, str]]:
    """取り直した期間の行を入れ替える(数は後から増えることがあるため、日ごとに丸ごと置き換える)。"""
    since = (dt.date.fromisoformat(today) - dt.timedelta(days=WEB_DAYS - 1)).isoformat()
    return [r for r in old if not (since <= r["date"] <= today)] + fresh


def totals_by_kind(rows: list[dict[str, str]], date: str) -> dict[str, int]:
    t = {"app": 0, "cli": 0}
    for r in rows:
        if r["date"] == date:
            t[r["kind"]] += int(r["downloads"])
    return t


def latest_on_or_before(dates: list[str], target: str) -> str | None:
    earlier = [d for d in dates if d <= target]
    return max(earlier) if earlier else None


def render_web(web: list[dict[str, str]], assets: list[dict[str, str]], today: str) -> list[str]:
    lines = ["", "## LP の訪問(Cloudflare Web Analytics)", ""]
    if not web:
        lines.append("まだ数がない(`cloudflare.json` とキーチェーンのトークンを置くと取り始める。docs/download-stats.md)。")
        return lines
    day = dt.date.fromisoformat(today)

    def window(days: int) -> list[dict[str, str]]:
        since = (day - dt.timedelta(days=days - 1)).isoformat()
        return [r for r in web if since <= r["date"] <= today]

    lines += [
        "訪問は、ほかのサイトから来た(またはアドレスを打って開いた)回数。ページビューは、再読み込みなども1回に数える。",
        "",
        "| ページ | 訪問(7日) | ページビュー(7日) | 訪問(30日) | ページビュー(30日) |",
        "|---|---:|---:|---:|---:|",
    ]
    w7, w30 = window(7), window(30)
    for page, label in (("ja", "日本語版 /"), ("en", "英語版 /en/"), ("other", "そのほか")):
        a = [r for r in w7 if page_of(r["path"]) == page]
        b = [r for r in w30 if page_of(r["path"]) == page]
        if not a and not b and page == "other":
            continue
        lines.append(
            f"| {label} | {sum(int(r['visits']) for r in a)} | {sum(int(r['pageviews']) for r in a)} "
            f"| {sum(int(r['visits']) for r in b)} | {sum(int(r['pageviews']) for r in b)} |"
        )

    dates = sorted({r["date"] for r in assets})
    base = latest_on_or_before(dates, (day - dt.timedelta(days=7)).isoformat())
    visits7 = sum(int(r["visits"]) for r in w7)
    if base is not None and base != today and visits7:
        now, b = totals_by_kind(assets, today), totals_by_kind(assets, base)
        dl = now["app"] - b["app"]
        lines += ["", f"直近 7 日のアプリのダウンロード {dl} 回 ÷ LP の訪問 {visits7} 回 = {dl / visits7:.1%}(brew や GitHub から直接落とした分も入るので目安)"]

    refs: dict[str, int] = {}
    for r in w30:
        refs[r["referer"]] = refs.get(r["referer"], 0) + int(r["visits"])
    lines += ["", "### 参照元(30日・訪問の多い順)", "", "| 参照元 | 訪問 |", "|---|---:|"]
    for ref, n in sorted(refs.items(), key=lambda x: -x[1])[:10]:
        lines.append(f"| {ref} | {n} |")
    return lines


def render_summary(
    assets: list[dict[str, str]], traffic: list[dict[str, str]], web: list[dict[str, str]], today: str
) -> str:
    dates = sorted({r["date"] for r in assets})
    now = totals_by_kind(assets, today)
    day = dt.date.fromisoformat(today)

    def delta(days: int) -> dict[str, str]:
        base = latest_on_or_before(dates, (day - dt.timedelta(days=days)).isoformat())
        if base is None or base == today:
            return {"app": "-", "cli": "-"}
        b = totals_by_kind(assets, base)
        return {k: f"+{now[k] - b[k]}" for k in now}

    d1, d7 = delta(1), delta(7)
    lines = [
        "---",
        f"date: {today}",
        "project: Kakiire",
        "tags: [knowledge]",
        'related: ["[[Projects/Kakiire/overview]]"]',
        "---",
        "",
        "# Kakiire のダウンロード数",
        "",
        f"`scripts/download-stats.py` が毎日書き換える(最終更新 {today})。元のデータは同じフォルダの `assets.csv`・`traffic.csv`・`web.csv`。",
        "数はダウンロードの回数で、人数ではない。brew で入れた分も含む(brew も GitHub Releases から落とす)。",
        "",
        "## 累計",
        "",
        "| 種類 | 累計 | 1日前から | 7日前から |",
        "|---|---:|---:|---:|",
        f"| アプリ(DMG・zip) | {now['app']} | {d1['app']} | {d7['app']} |",
        f"| CLI(zip) | {now['cli']} | {d1['cli']} | {d7['cli']} |",
        "",
        "## 版ごと",
        "",
        "| タグ | ファイル | 種類 | 累計 |",
        "|---|---|---|---:|",
    ]
    today_rows = [r for r in assets if r["date"] == today]
    def version_key(r: dict[str, str]) -> tuple:
        nums = tuple(int(x) if x.isdigit() else 0 for x in r["tag"].lstrip("v").split("."))
        return (nums, r["kind"], r["asset"])

    for r in sorted(today_rows, key=version_key, reverse=True):
        lines.append(f"| {r['tag']} | {r['asset']} | {r['kind']} | {r['downloads']} |")

    since = (day - dt.timedelta(days=13)).isoformat()
    recent = [r for r in traffic if r["date"] >= since]
    lines += [
        "",
        "## 直近 14 日の traffic",
        "",
        "tap の clones は、`brew tap` や `brew install sumihiro3/tap/...`(初回)と `brew update` の目安になる。",
        "",
        "| リポジトリ | 種類 | 回数 | 人数(日ごとの合計) |",
        "|---|---|---:|---:|",
    ]
    for repo in TRAFFIC_REPOS:
        for metric in ("clones", "views"):
            rs = [r for r in recent if r["repo"] == repo and r["metric"] == metric]
            count = sum(int(r["count"]) for r in rs)
            uniques = sum(int(r["uniques"]) for r in rs)
            lines.append(f"| {repo} | {metric} | {count} | {uniques} |")
    lines += render_web(web, assets, today)
    return "\n".join(lines) + "\n"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: download-stats.py <output-dir>", file=sys.stderr)
        return 2
    out = Path(sys.argv[1]).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    today = dt.date.today().isoformat()

    assets_path = out / "assets.csv"
    assets = [r for r in read_csv(assets_path) if r["date"] != today] + collect_assets(today)
    assets.sort(key=lambda r: (r["date"], r["tag"], r["asset"]))
    write_csv(assets_path, ASSET_FIELDS, assets)

    traffic_path = out / "traffic.csv"
    fresh = collect_traffic()
    keys = {(r["date"], r["repo"], r["metric"]) for r in fresh}
    traffic = [r for r in read_csv(traffic_path) if (r["date"], r["repo"], r["metric"]) not in keys] + fresh
    traffic.sort(key=lambda r: (r["date"], r["repo"], r["metric"]))
    write_csv(traffic_path, TRAFFIC_FIELDS, traffic)

    web_path = out / "web.csv"
    web = read_csv(web_path)
    settings = cloudflare_settings(out)
    if settings is None:
        print("web: cloudflare.json or keychain token missing, skipped", file=sys.stderr)
    else:
        try:
            web = merge_web(web, collect_web(*settings, today), today)
            web.sort(key=lambda r: (r["date"], r["path"], r["referer"]))
            write_csv(web_path, WEB_FIELDS, web)
        except Exception as e:  # 訪問数が取れなくても、ダウンロード数の記録は止めない
            print(f"web: failed: {e}", file=sys.stderr)

    (out / "summary.md").write_text(render_summary(assets, traffic, web, today))
    t = totals_by_kind(assets, today)
    print(f"{today} app={t['app']} cli={t['cli']} -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
