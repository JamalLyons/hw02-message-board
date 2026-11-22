#!/usr/bin/env python3
"""Generate android/app/google-services.json from .env.json (both gitignored).

Usage: python3 tool/gen_google_services.py [.env.json]
"""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
env = json.loads((root / (sys.argv[1] if len(sys.argv) > 1 else '.env.json')).read_text())
need = ['FIREBASE_ANDROID_API_KEY', 'FIREBASE_ANDROID_APP_ID', 'FIREBASE_MESSAGING_SENDER_ID',
        'FIREBASE_PROJECT_ID', 'FIREBASE_STORAGE_BUCKET', 'ANDROID_PACKAGE_NAME']
missing = [k for k in need if not env.get(k)]
if missing:
    sys.exit(f'.env.json is missing: {", ".join(missing)}')
out = {
    'project_info': {
        'project_number': env['FIREBASE_MESSAGING_SENDER_ID'],
        'project_id': env['FIREBASE_PROJECT_ID'],
        'storage_bucket': env['FIREBASE_STORAGE_BUCKET'],
    },
    'client': [{
        'client_info': {
            'mobilesdk_app_id': env['FIREBASE_ANDROID_APP_ID'],
            'android_client_info': {'package_name': env['ANDROID_PACKAGE_NAME']},
        },
        'oauth_client': [],
        'api_key': [{'current_key': env['FIREBASE_ANDROID_API_KEY']}],
        'services': {'appinvite_service': {'other_platform_oauth_client': []}},
    }],
    'configuration_version': '1',
}
dest = root / 'android/app/google-services.json'
dest.write_text(json.dumps(out, indent=2) + '\n')
print(f'wrote {dest.relative_to(root)}')
