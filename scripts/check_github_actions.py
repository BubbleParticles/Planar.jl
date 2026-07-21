#!/usr/bin/env python3
# coding: utf-8
"""
scripts/check_github_actions.py

Small CLI to reliably watch and tail GitHub Actions workflow runs using the GitHub REST API.

Usage examples:
  # Watch the latest run for workflow 'tests.yml' on master and print job logs when they complete
  python scripts/check_github_actions.py watch --workflow tests.yml --branch master --tail-logs

  # Watch a specific run id and print logs
  python scripts/check_github_actions.py watch --run 24606580666 --tail-logs

  # List latest run metadata
  python scripts/check_github_actions.py list --workflow tests.yml --branch master

Notes:
- Prefers GITHUB_TOKEN/GH_TOKEN env var. If not present, will attempt to delegate to 'gh' CLI if available.
- Downloads and extracts run logs (zip) and prints job log files when jobs complete.
"""

from __future__ import annotations
import argparse
import json
import os
import sys
import time
import tempfile
import zipfile
import shutil
import subprocess
from typing import Optional

# Try to import requests; if unavailable fall back to urllib
try:
    import requests
    HAVE_REQUESTS = True
except Exception:
    HAVE_REQUESTS = False


def run_cmd(cmd: str) -> tuple[int, str, str]:
    p = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def get_repo_from_git() -> str:
    code, out, err = run_cmd("git remote get-url origin")
    if code != 0 or not out:
        raise RuntimeError("Failed to determine git remote origin: %s" % err)
    url = out.strip()
    if url.startswith("git@"):
        # git@github.com:owner/repo.git
        part = url.split(":", 1)[1]
    elif "github.com/" in url:
        part = url.split("github.com/", 1)[1]
    else:
        part = url
    if part.endswith('.git'):
        part = part[:-4]
    return part


def get_token() -> Optional[str]:
    for key in ("GITHUB_TOKEN", "GH_TOKEN", "GITHUB_API_TOKEN"):
        val = os.environ.get(key)
        if val:
            return val
    # Try to extract token from gh if available (gh auth status --show-token)
    if shutil.which('gh'):
        code, out, err = run_cmd("gh auth status --show-token 2>/dev/null | sed -n 's/.*Token: //p'")
        if code == 0 and out:
            return out.strip()
    return None


def api_get_raw(url: str, token: Optional[str], params: Optional[dict] = None, stream: bool = False, accept: str = 'application/vnd.github.v3+json'):
    headers = {'Accept': accept}
    if token:
        headers['Authorization'] = f"token {token}"
    if HAVE_REQUESTS:
        resp = requests.get(url, headers=headers, params=params, stream=stream, timeout=60)
        resp.raise_for_status()
        return resp
    else:
        # Minimal urllib fallback (non-streaming)
        import urllib.request, urllib.parse
        if params:
            url = url + '?' + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers=headers)
        resp = urllib.request.urlopen(req, timeout=60)
        class R:
            def __init__(self, resp):
                self._r = resp
                self.status_code = resp.getcode()
                self.headers = resp.headers
            def json(self):
                return json.load(self._r)
            @property
            def content(self):
                return self._r.read()
            def iter_content(self, chunk_size=8192):
                while True:
                    chunk = self._r.read(chunk_size)
                    if not chunk:
                        break
                    yield chunk
        return R(resp)


def owner_repo_arg(repo_arg: Optional[str]) -> str:
    if repo_arg:
        return repo_arg
    return get_repo_from_git()


def get_latest_run(owner_repo: str, workflow: str, branch: str, token: Optional[str]):
    owner, repo = owner_repo.split('/', 1)
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/workflows/{workflow}/runs"
    params = {'branch': branch, 'per_page': 1}
    r = api_get_raw(url, token=token, params=params)
    data = r.json()
    runs = data.get('workflow_runs', [])
    return runs[0] if runs else None


def get_run(owner_repo: str, run_id: int, token: Optional[str]) -> dict:
    owner, repo = owner_repo.split('/', 1)
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/runs/{run_id}"
    r = api_get_raw(url, token=token)
    return r.json()


def get_jobs(owner_repo: str, run_id: int, token: Optional[str]) -> list:
    owner, repo = owner_repo.split('/', 1)
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/runs/{run_id}/jobs"
    r = api_get_raw(url, token=token, params={'per_page': 100})
    data = r.json()
    return data.get('jobs', [])


def download_run_logs(owner_repo: str, run_id: int, token: Optional[str], outdir: str) -> str:
    owner, repo = owner_repo.split('/', 1)
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/runs/{run_id}/logs"
    # This endpoint returns a zip archive (requests will follow redirects)
    r = api_get_raw(url, token=token, stream=True, accept='application/zip')
    zip_path = os.path.join(outdir, f"run_{run_id}_logs.zip")
    if HAVE_REQUESTS:
        with open(zip_path, 'wb') as fh:
            for chunk in r.iter_content(chunk_size=8192):
                if chunk:
                    fh.write(chunk)
    else:
        with open(zip_path, 'wb') as fh:
            fh.write(r.content)
    extract_dir = os.path.join(outdir, f"run_{run_id}_logs")
    os.makedirs(extract_dir, exist_ok=True)
    with zipfile.ZipFile(zip_path) as zf:
        zf.extractall(path=extract_dir)
    return extract_dir


def print_log_files_for_job(extract_dir: str, job_name: Optional[str] = None) -> None:
    for root, _, files in os.walk(extract_dir):
        for fname in files:
            if job_name and job_name not in fname:
                continue
            path = os.path.join(root, fname)
            print('\n' + '='*80)
            print(f"LOG: {fname}")
            print('='*80)
            try:
                with open(path, 'r', encoding='utf-8', errors='replace') as fh:
                    print(fh.read())
            except Exception as e:
                print(f"[error reading {path}]: {e}")


def watch_run(owner_repo: str, run_id: int, token: Optional[str], poll: int = 10, tail_logs: bool = False) -> int:
    printed_jobs = set()
    try:
        while True:
            run = get_run(owner_repo, run_id, token)
            status = run.get('status')
            conclusion = run.get('conclusion')
            html_url = run.get('html_url')
            updated_at = run.get('updated_at')
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Run {run_id}: status={status} conclusion={conclusion} updated={updated_at} url={html_url}")
            jobs = get_jobs(owner_repo, run_id, token)
            for job in jobs:
                jid = job.get('id')
                jname = job.get('name')
                jstatus = job.get('status')
                jconclusion = job.get('conclusion')
                print(f"  job {jid}: name={jname} status={jstatus} conclusion={jconclusion}")
                if jstatus == 'completed' and jid not in printed_jobs:
                    printed_jobs.add(jid)
                    if tail_logs:
                        td = tempfile.mkdtemp(prefix='gha-logs-')
                        try:
                            extract_dir = download_run_logs(owner_repo, run_id, token, td)
                            print_log_files_for_job(extract_dir, job_name=jname)
                        except Exception as e:
                            print(f"Failed to download/extract logs for run {run_id}: {e}")
                        finally:
                            shutil.rmtree(td, ignore_errors=True)
            if status == 'completed':
                if conclusion == 'success':
                    print('Run succeeded.')
                    return 0
                else:
                    print(f"Run completed with conclusion: {conclusion}")
                    if tail_logs:
                        td = tempfile.mkdtemp(prefix='gha-logs-')
                        try:
                            extract_dir = download_run_logs(owner_repo, run_id, token, td)
                            print_log_files_for_job(extract_dir, job_name=None)
                        except Exception as e:
                            print(f"Failed to download/extract logs for run {run_id}: {e}")
                        finally:
                            shutil.rmtree(td, ignore_errors=True)
                    return 2
            time.sleep(poll)
    except KeyboardInterrupt:
        print('Interrupted by user.')
        return 130


def main():
    parser = argparse.ArgumentParser(description='Check and tail GitHub Actions workflow runs reliably.')
    sub = parser.add_subparsers(dest='command')
    p_watch = sub.add_parser('watch', help='Watch a workflow run (wait until completion).')
    p_watch.add_argument('--repo', help='owner/repo (defaults to git remote origin)')
    p_watch.add_argument('--workflow', help='workflow file name or id (e.g., tests.yml)')
    p_watch.add_argument('--branch', default='master')
    p_watch.add_argument('--run', type=int, help='specific run id to watch')
    p_watch.add_argument('--poll', type=int, default=10)
    p_watch.add_argument('--tail-logs', action='store_true', help='Download and print logs for completed jobs')
    p_list = sub.add_parser('list', help='List latest run for a workflow')
    p_list.add_argument('--repo')
    p_list.add_argument('--workflow', required=True)
    p_list.add_argument('--branch', default='master')
    args = parser.parse_args()

    token = get_token()
    if not token:
        print('Error: No GITHUB_TOKEN/GH_TOKEN found. Please set GITHUB_TOKEN or authenticate gh CLI.')
        if shutil.which('gh'):
            print('Delegating to gh CLI (will require gh auth):')
            if args.command == 'watch' and args.run:
                os.execvp('gh', ['gh', 'run', 'watch', str(args.run)])
            elif args.command == 'watch' and args.workflow:
                print('Falling back to gh run watch for workflow (no run id provided).')
                os.execvp('gh', ['gh', 'run', 'list', '--workflow', args.workflow, '--branch', args.branch])
        sys.exit(2)

    owner_repo = owner_repo_arg(args.repo)

    if args.command == 'list':
        run = get_latest_run(owner_repo, args.workflow, args.branch, token)
        if not run:
            print('No runs found.')
            sys.exit(1)
        print(json.dumps(run, indent=2))
        sys.exit(0)
    elif args.command == 'watch':
        if args.run:
            run_id = args.run
        else:
            if not args.workflow:
                print('Either --run or --workflow must be provided.')
                sys.exit(2)
            run = get_latest_run(owner_repo, args.workflow, args.branch, token)
            if not run:
                print('No runs found for workflow.')
                sys.exit(1)
            run_id = run.get('id')
        rc = watch_run(owner_repo, run_id, token, poll=args.poll, tail_logs=args.tail_logs)
        sys.exit(rc)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()
