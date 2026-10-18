"""Run the installed CLI while emitting numeric progress, without extra inference."""
import contextlib
import json


def progress_handler(_config, *args, **kwargs):
    def handle(event):
        if event.get('type') not in ('progress_start', 'progress_update', 'progress_end'):
            return
        fields = ('type', 'stage', 'stage_current', 'stage_total', 'overall_progress', 'part_index', 'total_parts')
        payload = {key: event[key] for key in fields if key in event}
        print('BRIDGE_PROGRESS ' + json.dumps(payload, ensure_ascii=True), flush=True)
    return contextlib.nullcontext(), handle


if __name__ == '__main__':
    import pdf2zh_next.high_level as high_level
    high_level.create_progress_handler = progress_handler
    from pdf2zh_next.main import cli
    cli()
