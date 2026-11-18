"""Fixed questionnaire contract for the paired Android demo (Li 2012, p. 651)."""
from datetime import datetime

LIFE = {"interests", "avoid", "food", "budget", "social", "schedule", "planning", "ai_help"}
COMMUNICATION = {"support", "conflict", "care", "decision", "changes", "ai_role"}
META = {
    "instrument_id": "mini_ipip_20", "language": "zh",
    "translation_source": "Li_2012_appendix_p651", "version": "Li2012",
    "score_version": "mean_reverse_1",
}
TRAITS = {
    "E": (1, 6, 11, 16), "A": (2, 7, 12, 17), "C": (3, 8, 13, 18),
    "N": (4, 9, 14, 19), "I": (5, 10, 15, 20),
}
REVERSE = {6, 7, 8, 9, 10, 15, 16, 17, 18, 19, 20}


def preferences(value, allowed):
    if not isinstance(value, dict) or not value.keys() <= allowed:
        raise ValueError("未知偏好字段")
    cleaned = {}
    for key, text in value.items():
        if not isinstance(text, str) or len(text) > 240:
            raise ValueError("每项偏好最多 240 字")
        if text.strip():
            cleaned[key] = text.strip()
    return cleaned


def validate_profile(data):
    if not isinstance(data, dict) or not data.keys() <= {"life", "communication", "mini_ipip"}:
        raise ValueError("档案结构无效")
    result = {"life": preferences(data.get("life", {}), LIFE),
              "communication": preferences(data.get("communication", {}), COMMUNICATION)}
    if "mini_ipip" not in data:
        return result
    scale = data["mini_ipip"]
    if (not isinstance(scale, dict)
            or not scale.keys() <= {*META, "answers", "responded_at"}
            or any(scale.get(k) != v for k, v in META.items())):
        raise ValueError("量表版本无效")
    answers = scale.get("answers")
    if (not isinstance(answers, list) or len(answers) != 20
            or any(v is not None and (type(v) is not int or not 1 <= v <= 5) for v in answers)):
        raise ValueError("需要 20 个作答位置，答案为 1 至 5 或留空")
    mini = {**META, "answers": list(answers)}
    if scale.get("responded_at") is not None:
        try:
            timestamp = scale["responded_at"]
            if not isinstance(timestamp, str) or len(timestamp) > 40 or datetime.fromisoformat(timestamp).tzinfo is None:
                raise ValueError
        except (TypeError, ValueError):
            raise ValueError("作答时间无效") from None
        mini["responded_at"] = timestamp
    result["mini_ipip"] = mini
    return result


def public_projection(validated):
    """Only derived, complete scores leave the owner; unpublished drafts never enter here."""
    result = {key: dict(validated.get(key, {})) for key in ("life", "communication")}
    mini = validated.get("mini_ipip", {})
    answers = mini.get("answers", [])
    if len(answers) == 20 and all(type(v) is int and 1 <= v <= 5 for v in answers):
        scores = {trait: sum((6 - answers[i - 1] if i in REVERSE else answers[i - 1])
                             for i in indices) / 4 for trait, indices in TRAITS.items()}
        result["mini_ipip"] = {**META, "scores": scores}
        if mini.get("responded_at"):
            result["mini_ipip"]["responded_at"] = mini["responded_at"]
    return result
