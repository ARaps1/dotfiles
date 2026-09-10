"""LiteLLM proxy callback that records minuet autocomplete token usage and cost."""

import json
import os
import time

from litellm.integrations.custom_logger import CustomLogger

# One JSON object per completion is appended here (written locally by the proxy).
USAGE_FILE = os.path.expanduser("~/.local/state/minuet-usage.jsonl")

# Fallback USD price per 1M tokens, keyed by the litellm model_name, used only when the
# proxy does not compute a cost for the model; these may lag current AWS Bedrock pricing.
FALLBACK_PRICES = {
    "bedrock-haiku": {"in": 1.00, "out": 5.00},
    "bedrock-sonnet": {"in": 3.00, "out": 15.00},
}


class MinuetUsageLogger(CustomLogger):
    def log_success_event(self, kwargs, response_obj, start_time, end_time):
        self._record(kwargs, response_obj)

    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        self._record(kwargs, response_obj)

    def _record(self, kwargs, response_obj):
        try:
            usage = getattr(response_obj, "usage", None)
            if usage is None:
                streamed = kwargs.get("complete_streaming_response")
                usage = getattr(streamed, "usage", None) if streamed else None
            prompt = int(getattr(usage, "prompt_tokens", 0) or 0)
            completion = int(getattr(usage, "completion_tokens", 0) or 0)

            model = (
                ((kwargs.get("litellm_params") or {}).get("metadata") or {}).get("model_group")
                or kwargs.get("model")
                or "unknown"
            )

            cost = kwargs.get("response_cost")
            if not cost:
                prices = FALLBACK_PRICES.get(model)
                if prices:
                    cost = prompt / 1e6 * prices["in"] + completion / 1e6 * prices["out"]

            entry = {
                "ts": time.time(),
                "model": model,
                "in": prompt,
                "out": completion,
                "cost": round(float(cost), 6) if cost else 0.0,
            }
            os.makedirs(os.path.dirname(USAGE_FILE), exist_ok=True)
            with open(USAGE_FILE, "a", encoding="utf-8") as handle:
                handle.write(json.dumps(entry) + "\n")
        except Exception:
            # Usage logging must never break a completion.
            pass


instance = MinuetUsageLogger()
