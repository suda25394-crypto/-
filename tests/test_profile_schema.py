import unittest
from services.couple.profile_schema import META, REVERSE, public_projection, validate_profile


class ProfileTests(unittest.TestCase):
    def scale(self, answers):
        return {"life": {"avoid": " 人多 "}, "mini_ipip": {**META, "answers": answers}}

    def test_scoring_keys_and_privacy(self):
        data = validate_profile(self.scale([1 if i in REVERSE else 5 for i in range(1, 21)]))
        projected = public_projection(data)
        self.assertEqual(projected["mini_ipip"]["scores"], dict.fromkeys("EACNI", 5))
        self.assertNotIn("answers", projected["mini_ipip"])
        self.assertEqual(projected["life"]["avoid"], "人多")
        graded = public_projection(validate_profile(self.scale([1] * 20)))["mini_ipip"]["scores"]
        self.assertEqual(graded, dict(E=3, A=3, C=3, N=3, I=4))

    def test_incomplete_answers_stay_private(self):
        data = validate_profile(self.scale([3]*19 + [None]))
        self.assertEqual(len(data["mini_ipip"]["answers"]), 20)
        self.assertNotIn("mini_ipip", public_projection(data))

    def test_reject_forged_fields_and_invalid_answers(self):
        for bad in [self.scale([True]*20), self.scale([3]*19), self.scale([6]*20),
                    {"life": {"other_person": "guess"}}, {"scores":{"E":5}},
                    {"mini_ipip": {**META, "answers":[3]*20,"scores":{"E":5}}}]:
            with self.subTest(bad=type(bad)), self.assertRaises(ValueError):
                validate_profile(bad)
