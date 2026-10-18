"""Run the installed PDF2zh backend on loopback only, without updating it."""
import os
import runpy
import sys
import flask
import json
import threading
from backend_control import install_control

backend = os.environ.get('PDF2ZH_BACKEND_PATH')
if not backend or not os.path.isfile(os.path.join(backend, 'server.py')):
    raise RuntimeError('Set PDF2ZH_BACKEND_PATH to the installed PDF2zh server directory.')
original_run = flask.Flask.run

def local_run(self, *args, **kwargs):
    data_dir = os.environ['ZOTERO_CHATGPT_DATA_DIR']
    with open(os.path.join(data_dir, 'bridge.json'), encoding='utf-8') as settings_file:
        api_key = json.load(settings_file)['apiKey']
    def schedule_stop():
        threading.Timer(0.5, lambda: os._exit(0)).start()
    install_control(self, api_key, schedule_stop)
    kwargs['host'] = '127.0.0.1'
    return original_run(self, *args, **kwargs)

flask.Flask.run = local_run
sys.path.insert(0, backend)
os.chdir(backend)
sys.argv = [os.path.join(backend, 'server.py'), '--port', '8767', '--env_tool', 'conda', '--skip_install', 'True', '--check_update', 'False']
runpy.run_path(sys.argv[0], run_name='__main__')
