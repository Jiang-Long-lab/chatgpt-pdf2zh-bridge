"""Connect structured CLI events to the existing backend task manager."""
import json
import math
import os
import subprocess


def progress_update(event):
    update = {'status': 'running', 'message': str(event.get('stage', '处理中'))}
    overall = event.get('overall_progress')
    if isinstance(overall, (int, float)) and math.isfinite(overall):
        update['progress'] = max(0, min(99, overall))
        update['progressKnown'] = True
    current, total = event.get('stage_current'), event.get('stage_total')
    if event.get('type') == 'progress_start':
        current = 0
    if event.get('type') == 'progress_end':
        current = total
    percent = None
    if all(isinstance(x, (int, float)) and math.isfinite(x) for x in (current, total)) and total > 0:
        percent = max(0, min(100, current / total * 100))
    update['stageProgress'] = percent
    update['stageCurrent'] = current
    update['stageTotal'] = total
    update['partIndex'] = event.get('part_index')
    update['totalParts'] = event.get('total_parts')
    return update


def install_capture(execute_module, task_manager):
    original = execute_module.execute_with_progress
    runner = os.path.join(os.path.dirname(__file__), 'pdf2zh_next_progress.py')
    def execute(cmd, task_id, args, env_manager):
        if cmd[0] != 'pdf2zh_next' or not args.enable_venv or not env_manager:
            return original(cmd, task_id, args, env_manager)
        command, env = env_manager.get_command_and_env([runner, *cmd[1:]])
        env['PYTHONIOENCODING'] = 'utf-8'
        stages = {}
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              env=env, text=True, encoding='utf-8', errors='replace',
                              creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0)) as process:
            for line in process.stdout:
                if line.startswith('BRIDGE_PROGRESS '):
                    try:
                        update = progress_update(json.loads(line[len('BRIDGE_PROGRESS '):]))
                        stages[update['message']] = {'name': update['message'], 'percent': update['stageProgress'], 'partIndex': update['partIndex'], 'totalParts': update['totalParts']}
                        update['stages'] = list(stages.values())
                        task_manager.update_task(task_id, update)
                    except (ValueError, TypeError):
                        pass
                else:
                    print(line, end='', flush=True)
            code = process.wait()
            if code:
                raise subprocess.CalledProcessError(code, command)
    execute_module.execute_with_progress = execute
