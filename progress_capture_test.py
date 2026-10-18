import unittest
from progress_capture import progress_update


class ProgressTests(unittest.TestCase):
    def test_stage_percentage_does_not_replace_overall(self):
        event = {'type': 'progress_update', 'stage': 'Typesetting', 'stage_current': 3,
                 'stage_total': 4, 'overall_progress': 91}
        result = progress_update(event)
        self.assertEqual(result['stageProgress'], 75)
        self.assertEqual(result['progress'], 91)

    def test_unknown_total_and_completion(self):
        self.assertIsNone(progress_update({'type': 'progress_start'})['stageProgress'])
        result = progress_update({'type': 'progress_end', 'stage_total': 4, 'overall_progress': 100})
        self.assertEqual(result['stageProgress'], 100)
        self.assertEqual(result['progress'], 99)  # backend confirms final file completion


if __name__ == '__main__':
    unittest.main()
