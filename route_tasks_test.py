import json
import threading
import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from flask import Flask
from backend_control import install_control
from progress_capture import install_capture
from route_tasks import install_route_tasks


class Tasks:
    def __init__(self):
        self.tasks, self.history = {}, []
    def add_task(self, task_id, task):
        self.tasks[task_id] = task
    def update_task(self, task_id, update):
        assert task_id in self.tasks, 'Progress event lost its request task ID'
        self.tasks[task_id].update(update)
    def complete_task(self, task_id, status, message, file_list=None):
        task = self.tasks[task_id]
        task.update(active=False, status='完成' if status == 'success' else '失败', progress=100)
        self.history.append({'fileName': task['fileName'], 'status': status})
    def get_active_tasks_list(self):
        return list(self.tasks.values())
    def get_history(self):
        return self.history


class RouteTests(unittest.TestCase):
    def test_compare_progress_without_upstream_task_id_and_busy_shutdown(self):
        app, manager = Flask(__name__), Tasks()
        install_control(app, 'key', lambda: None, manager)
        install_route_tasks(app, manager)
        execute = SimpleNamespace(execute_with_progress=lambda *args: self.fail('Unexpected fallback'))
        install_capture(execute, manager)
        env = SimpleNamespace(get_command_and_env=lambda args: (args, {}))
        process = MagicMock()
        process.__enter__.return_value = process
        process.stdout = ['BRIDGE_PROGRESS ' + json.dumps({'type': 'progress_update', 'stage': 'Translate Paragraphs', 'stage_current': 2, 'stage_total': 4, 'overall_progress': 40})]
        process.wait.return_value = 0
        entered, release = threading.Event(), threading.Event()
        @app.post('/compare')
        def compare():
            # Upstream /compare calls the engine with task_id=None.
            execute.execute_with_progress(['pdf2zh_next', 'sample.pdf'], None, SimpleNamespace(enable_venv=True), env)
            entered.set()
            release.wait(3)  # final assembly/rename is still in progress
            return {'status': 'success', 'fileList': ['sample.compare.pdf']}
        with patch('progress_capture.subprocess.Popen', return_value=process):
            worker = threading.Thread(target=lambda: app.test_client().post('/compare', json={'fileName': 'sample.pdf'}))
            worker.start()
            try:
                self.assertTrue(entered.wait(2))
                client = app.test_client()
                data = client.get('/bridge/progress', headers={'Authorization': 'Bearer key'}).json
                self.assertTrue(data['tasks'][0]['active'])
                self.assertEqual(data['tasks'][0]['stages'][0]['percent'], 50)
                self.assertEqual(client.post('/bridge/shutdown', headers={'Authorization': 'Bearer key'}).status_code, 409)
            finally:
                release.set()
                worker.join()
        self.assertEqual(manager.history[0]['status'], 'success')
        self.assertEqual(next(iter(manager.tasks.values()))['progress'], 100)

    def test_all_extra_routes_and_failure_are_recorded_without_duplicate_translate(self):
        for route in ['/crop', '/crop-compare', '/compare']:
            for status in [200, 500]:
                with self.subTest(route=route, status=status):
                    app, manager = Flask(__name__), Tasks()
                    install_route_tasks(app, manager)
                    app.add_url_rule(route, 'work', lambda: ({'status': 'success' if status == 200 else 'error'}, status), methods=['POST'])
                    app.test_client().post(route, json={'fileName': 'sample.pdf'})
                    self.assertEqual(len(manager.history), 1)
                    self.assertEqual(manager.history[0]['status'], 'success' if status == 200 else 'failed')
        app, manager = Flask(__name__), Tasks()
        install_route_tasks(app, manager)
        app.add_url_rule('/translate', 'normal', lambda: {'status': 'success'}, methods=['POST'])
        app.test_client().post('/translate', json={'fileName': 'sample.pdf'})
        self.assertFalse(manager.tasks)


if __name__ == '__main__':
    unittest.main()
