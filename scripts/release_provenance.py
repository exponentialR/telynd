#!/usr/bin/env python3
"""Trusted workflow-side checks. Never execute code from the requested tag."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess


class PolicyError(ValueError):
    pass


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def resolve(tag, approved_main, expected_revision=None, expected_tag_object=None):
    if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', tag):
        raise PolicyError('Use a version tag in the form vMAJOR.MINOR.PATCH')
    if not re.fullmatch(r'[0-9a-f]{40}', approved_main):
        raise PolicyError('Invalid approved main revision')
    revision = git('rev-parse', '--verify', f'refs/tags/{tag}^{{commit}}')
    tag_object = git('rev-parse', '--verify', f'refs/tags/{tag}')
    if subprocess.run(['git', 'merge-base', '--is-ancestor', revision, approved_main], check=False).returncode:
        raise PolicyError('The tagged revision is outside the approved main history')
    if expected_revision and revision != expected_revision:
        raise PolicyError('The tag no longer identifies the validated revision')
    if expected_tag_object and tag_object != expected_tag_object:
        raise PolicyError('The tag object changed after validation')
    return {'revision': revision, 'tag_object': tag_object}


def validate_rules(main_rules, tag_rules):
    for rules, target, allowed in [(main_rules, 'branch', {'refs/heads/main', '~ALL'}), (tag_rules, 'tag', {'refs/tags/v*', '~ALL'})]:
        refs = rules.get('conditions', {}).get('ref_name', {})
        if (rules.get('target') != target or rules.get('enforcement') != 'active'
                or refs.get('exclude') or not (set(refs.get('include', [])) & allowed)):
            raise PolicyError(f'An active, applicable {target} ruleset with no exclusions is required')
        # GitHub hides this property from read-only callers. Maintainers must
        # separately confirm no bypass actors when provisioning the environment.
        if rules.get('bypass_actors'):
            raise PolicyError('Release rulesets must not configure bypass actors')
    branch = {rule['type']: rule for rule in main_rules.get('rules', [])}
    pr = branch.get('pull_request', {}).get('parameters', {})
    checks = branch.get('required_status_checks', {}).get('parameters', {})
    contexts = {item.get('context') for item in checks.get('required_status_checks', [])}
    if pr.get('required_approving_review_count', 0) < 1 or not pr.get('dismiss_stale_reviews_on_push'):
        raise PolicyError('Main must require review approval and dismiss stale approvals')
    if not {'mac-app', 'recovery'} <= contexts or not checks.get('strict_required_status_checks_policy'):
        raise PolicyError('Main must require current mac-app and recovery checks')
    if not {'update', 'deletion'} <= {r['type'] for r in tag_rules.get('rules', [])}:
        raise PolicyError('Release tags must block updates and deletion')


def api(path):
    return json.loads(subprocess.check_output(['gh', 'api', path], text=True))


def github_policy(tag, approved_main, result, main_ruleset, tag_ruleset):
    repository = os.environ.get('GITHUB_REPOSITORY', '')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise PolicyError('Missing GitHub repository context')
    if os.environ.get('GITHUB_REF') != 'refs/heads/main' or os.environ.get('GITHUB_SHA') != approved_main:
        raise PolicyError('Release preparation must use the trusted main workflow revision')
    if os.environ.get('GITHUB_EVENT_NAME') != 'workflow_dispatch':
        raise PolicyError('Release preparation requires an explicit manual dispatch')
    if not all(value and value.isdecimal() for value in (main_ruleset, tag_ruleset)):
        raise PolicyError('Configure RELEASE_MAIN_RULESET_ID and RELEASE_TAG_RULESET_ID first')
    prefix = f'repos/{repository}'
    branch = api(f'{prefix}/branches/main')
    if not branch.get('protected'):
        raise PolicyError('Main is not protected')
    if subprocess.run(['git', 'merge-base', '--is-ancestor', approved_main, branch['commit']['sha']], check=False).returncode:
        raise PolicyError('The workflow revision is no longer in main history')
    validate_rules(api(f'{prefix}/rulesets/{main_ruleset}'), api(f'{prefix}/rulesets/{tag_ruleset}'))
    if api(f'{prefix}/git/ref/tags/{tag}')['object']['sha'] != result['tag_object']:
        raise PolicyError('The remote tag changed after checkout')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tag', required=True)
    parser.add_argument('--approved-main', required=True)
    parser.add_argument('--expected-revision')
    parser.add_argument('--expected-tag-object')
    parser.add_argument('--github-output')
    args = parser.parse_args()
    result = resolve(args.tag, args.approved_main, args.expected_revision, args.expected_tag_object)
    github_policy(args.tag, args.approved_main, result, os.environ.get('RELEASE_MAIN_RULESET_ID'), os.environ.get('RELEASE_TAG_RULESET_ID'))
    if args.github_output:
        with Path(args.github_output).open('a') as output:
            for key, value in result.items():
                output.write(f'{key}={value}\n')
    print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except (PolicyError, subprocess.CalledProcessError, KeyError) as error:
        raise SystemExit(f'Release provenance rejected: {error}')
