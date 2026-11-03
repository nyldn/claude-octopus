#!/usr/bin/env python3
"""Return key presence only; executed with the installed Vibe interpreter."""
import sys


def has_key():
    import vibe.utils.keyring as store

    disabled = getattr(store, '_is_keyring_disabled', None)
    if callable(disabled) and disabled():
        return False
    probe = getattr(store, 'probe_api_key_from_keyring', None)
    if callable(probe):
        value = probe('MISTRAL_API_KEY')
    else:
        # Older Vibe has no read-only public probe. Read with its native backend
        # directly rather than get_api_key_from_keyring, which can migrate keys.
        services = (store._KEYRING_SERVICE, *getattr(store, '_LEGACY_KEYRING_SERVICES', ()))
        value = None
        for service in services:
            value = store._get_password(service, 'MISTRAL_API_KEY')
            if value is not None:
                break
    return isinstance(value, str) and bool(value.strip())


if __name__ == '__main__':
    try:
        present = has_key()
    except Exception:
        present = False
    sys.exit(0 if present else 1)
