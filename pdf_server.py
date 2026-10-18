"""Run the installed PDF2zh backend on loopback only, without updating it."""
import os
import runpy
import sys
import flask

backend = os.environ.get('PDF2ZH_BACKEND_PATH')
if not backend or not os.path.isfile(os.path.join(backend, 'server.py')):
    raise RuntimeError('Set PDF2ZH_BACKEND_PATH to the installed PDF2zh server directory.')
original_run = flask.Flask.run

def local_run(self, *args, **kwargs):
    kwargs['host'] = '127.0.0.1'
    return original_run(self, *args, **kwargs)

flask.Flask.run = local_run
sys.path.insert(0, backend)
os.chdir(backend)
sys.argv = [os.path.join(backend, 'server.py'), '--port', '8767', '--env_tool', 'conda', '--skip_install', 'True', '--check_update', 'False']
runpy.run_path(sys.argv[0], run_name='__main__')
