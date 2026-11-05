#!/usr/bin/env python3
"""Small internal adapters for portable workflow boundaries."""
import argparse
import importlib.util
import json
import os
import re
import sys

spec = importlib.util.spec_from_file_location('feature_contract', os.path.join(os.path.dirname(__file__), 'feature-contract.py'))
storage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(storage)


def extract_findings(text, label):
    """Use the analysis parser's raw fence and strict JSON contract at runtime."""
    spec = importlib.util.spec_from_file_location('feature_analysis', os.path.join(os.path.dirname(__file__), 'feature-analysis.py'))
    analysis = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = analysis
    spec.loader.exec_module(analysis)
    document = analysis.Document('response', text, text.encode('utf-8'))
    result, warnings = [], []
    for parsed, _ in analysis.fences(document, label, warnings):
        if isinstance(parsed, dict):
            parsed = parsed.get('findings')
        if (not isinstance(parsed, list) or not all(isinstance(item, dict) for item in parsed)
                or len(result) + len(parsed) > 100):
            raise ValueError('invalid bounded findings')
        result.extend(parsed)
    if warnings:
        raise ValueError('invalid findings block')
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument('command', choices=('extract', 'snapshot', 'research-text', 'render-tasks', 'completion', 'analysis'))
    p.add_argument('--input')
    p.add_argument('--label')
    p.add_argument('--root')
    p.add_argument('--path')
    p.add_argument('--baseline')
    p.add_argument('--completion')
    p.add_argument('--report')
    p.add_argument('--summary')
    args = p.parse_args()
    try:
        if args.command == 'snapshot':
            with storage.Root(os.path.abspath(args.root)) as root:
                path = args.path
                if os.path.isabs(path):
                    prefix = root.path + os.sep
                    if not path.startswith(prefix):
                        raise ValueError('plan leaves its approved root')
                    path = path[len(prefix):]
                data = root.read(path)
            data.decode('utf-8', errors='strict')
            sys.stdout.buffer.write(data)
            return 0
        text = storage.read_input(args.input).decode('utf-8', errors='strict')
        if args.command == 'analysis':
            receipt = json.loads(text)
            report = json.loads(storage.read_input(args.report)) if args.report else {}
            summary = json.loads(storage.read_input(args.summary)) if args.summary else {}
            result = {key: receipt.get(key) for key in ('analysis_digest', 'status', 'reason', 'trigger', 'attempts', 'selected')}
            result.update(deterministic_findings=report.get('findings', []), semantic_findings=summary.get('findings', []), verification=summary.get('verification', 'deterministic_only'))
            print(json.dumps({'analysis': result}))
            return 0
        if args.command == 'completion':
            raw = json.loads(text)
            if not re.fullmatch(r'[0-9a-f]{40,64}', args.baseline or ''):
                raise ValueError('invalid baseline')
            result = {'schema_version': 1, 'contract_digest': raw['contract_digest'], 'tasks': []}
            for task in raw.get('tasks', []):
                prior = task.get('historical_evidence')
                if isinstance(prior, dict):
                    evidence = prior
                else:
                    paths = task.get('write_evidence', {}).get('paths', {})
                    files = []
                    for path, item in paths.items():
                        storage.relative(path)
                        if not isinstance(item, dict) or item.get('type') not in ('file', 'directory', 'missing'):
                            raise ValueError('invalid evidence')
                        files.append(dict(relativepath=path, **{key: item[key] for key in ('type', 'mode', 'digest') if key in item}))
                    evidence = {'run_id': str(task.get('evidence', '')).split(':', 1)[-1],
                                'baseline_commit': args.baseline, 'files': files}
                result['tasks'].append({key: task[key] for key in ('id', 'identity', 'status', 'contract_digest')})
                result['tasks'][-1]['evidence'] = evidence
            print(json.dumps(result))
            return 0
        if args.command == 'render-tasks':
            contract = json.loads(text)
            print('# Tasks\n')
            completed = json.loads(storage.read_input(args.completion)) if args.completion else {}
            completed_ids = {task['id'] for task in completed.get('tasks', []) if task.get('status') == 'completed' and task.get('contract_digest') == contract.get('contract_digest') and any(item['id'] == task['id'] and item['identity'] == task.get('identity') for item in contract['tasks'])}
            for task in contract['tasks']:
                print('- [' + ('x' if task['id'] in completed_ids else ' ') + '] ' + task['id'] + ' ' + task['title'] + ' ' + ' '.join('[' + r + ']' for r in task['requirements']))
            print('\n```octopus-tasks\n' + json.dumps(contract, indent=2) + '\n```')
            return 0
        if args.command == 'research-text':
            lines = text.splitlines()
            lines = [line for line in lines if not line.startswith(('# PROBE Phase Synthesis', '## Discovery Summary', '## Original Task:', '*Synthesized from '))]
            while lines and (not lines[-1].strip() or lines[-1].strip() == '---'):
                lines.pop()
            result = '\n'.join(lines).strip()
            if not result:
                raise ValueError('accepted synthesis is empty')
            print(result)
            return 0
        if not re.fullmatch(r'octopus-[a-z-]+', args.label):
            raise ValueError('unsupported block label')
        print(json.dumps(extract_findings(text, args.label)))
        return 0
    except (OSError, UnicodeError, ValueError, TypeError):
        print('[]')
        return 2


if __name__ == '__main__':
    sys.exit(main())
