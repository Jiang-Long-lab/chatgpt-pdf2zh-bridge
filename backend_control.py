"""Authenticated, idle-only shutdown for the locally owned PDF backend."""
import hmac
import threading
from flask import g, jsonify, request


def install_control(app, api_key, on_stop):
    lock = threading.Lock()
    state = {'active': 0, 'stopping': False}

    @app.before_request
    def track_work():
        if request.path == '/bridge/shutdown':
            return None
        # Track all work requests, including parsing/layout before or after inference.
        if request.method == 'POST':
            with lock:
                if state['stopping']:
                    return jsonify(error='Service is stopping.'), 503
                state['active'] += 1
                g.bridge_work = True

    @app.teardown_request
    def finish_work(_error):
        if getattr(g, 'bridge_work', False):
            with lock:
                state['active'] -= 1
                g.bridge_work = False

    @app.post('/bridge/shutdown')
    def shutdown():
        if not hmac.compare_digest(request.headers.get('Authorization', ''), 'Bearer ' + api_key):
            return jsonify(error='Invalid local key.'), 401
        with lock:
            if state['active']:
                return jsonify(error='A PDF task is still running. Wait for it to finish.'), 409
            if not state['stopping']:
                state['stopping'] = True
                on_stop()
        return jsonify(status='stopping')
