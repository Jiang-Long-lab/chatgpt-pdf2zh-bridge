"""Track upstream PDF actions that do not create their own task IDs."""
import ntpath
import uuid
from datetime import datetime
from flask import g, request


def install_route_tasks(app, task_manager):
    routes = {'/compare': '生成双语对照', '/crop-compare': '裁剪并生成对照', '/crop': '裁剪 PDF'}

    @app.before_request
    def start_task():
        if request.method != 'POST' or request.path not in routes:
            return
        body = request.get_json(silent=True) or {}
        if not isinstance(body, dict):
            body = {}
        task_id = str(uuid.uuid4())
        g.bridge_task_id = task_id
        task_manager.add_task(task_id, {
            'taskId': task_id, 'active': True,
            'fileName': ntpath.basename(str(body.get('fileName') or 'PDF 文件')),
            'startTime': datetime.now().isoformat(), 'progress': 0, 'progressKnown': False,
            'status': 'running', 'message': routes[request.path],
        })

    @app.after_request
    def finish_task(response):
        task_id = getattr(g, 'bridge_task_id', None)
        if task_id:
            result = response.get_json(silent=True)
            success = response.status_code < 400 and isinstance(result, dict) and result.get('status') == 'success'
            task_manager.complete_task(task_id, 'success' if success else 'failed',
                                       '处理完成' if success else '处理失败，请查看后端日志。',
                                       file_list=result.get('fileList', []) if success else None)
            g.bridge_task_finished = True
        return response

    @app.teardown_request
    def finish_exception(error):
        task_id = getattr(g, 'bridge_task_id', None)
        if task_id and not getattr(g, 'bridge_task_finished', False):
            task_manager.complete_task(task_id, 'failed', '请求异常结束，请查看后端日志。')
