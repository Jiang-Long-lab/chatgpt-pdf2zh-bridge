import threading
import unittest
from flask import Flask
from backend_control import install_control


class ShutdownTests(unittest.TestCase):
    def test_authentication_and_repeat_shutdown(self):
        app = Flask(__name__)
        stopped = []
        install_control(app, 'test-key', lambda: stopped.append(True))
        client = app.test_client()
        self.assertEqual(client.post('/bridge/shutdown').status_code, 401)
        self.assertFalse(stopped)
        for _ in range(2):
            self.assertEqual(client.post('/bridge/shutdown', headers={'Authorization': 'Bearer test-key'}).status_code, 200)
        self.assertEqual(len(stopped), 1)
        self.assertEqual(client.post('/translate').status_code, 503)

    def test_busy_pdf_is_preserved_then_shutdown_succeeds(self):
        app = Flask(__name__)
        stopped = []
        entered, release = threading.Event(), threading.Event()
        @app.post('/translate')
        def translate():
            entered.set()
            release.wait(5)
            return 'done'
        install_control(app, 'test-key', lambda: stopped.append(True))
        worker = threading.Thread(target=lambda: app.test_client().post('/translate'))
        worker.start()
        self.assertTrue(entered.wait(2))
        client = app.test_client()
        try:
            self.assertEqual(client.post('/bridge/shutdown', headers={'Authorization': 'Bearer test-key'}).status_code, 409)
            self.assertFalse(stopped)
        finally:
            release.set()
            worker.join()
        self.assertEqual(client.post('/bridge/shutdown', headers={'Authorization': 'Bearer test-key'}).status_code, 200)


if __name__ == '__main__':
    unittest.main()
