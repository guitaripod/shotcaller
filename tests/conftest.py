from __future__ import annotations

import json
from concurrent.futures import Executor, Future
from pathlib import Path

import pytest

from shotcaller.events import parse_line
from shotcaller.state import MatchState


class InlineExecutor(Executor):
    """Runs submitted calls immediately so service tests are deterministic."""

    def submit(self, fn, /, *args, **kwargs):
        future: Future = Future()
        try:
            future.set_result(fn(*args, **kwargs))
        except Exception as error:
            future.set_exception(error)
        return future


@pytest.fixture
def inline() -> InlineExecutor:
    return InlineExecutor()


def lines_to_state(lines: list[str]) -> MatchState:
    state = MatchState()
    for line in lines:
        event = parse_line(line)
        assert event is not None, line
        state.apply(event)
    return state


MATCH_LINES = [
    "0|hello|v=0.1.0|map=mp_rust|gametype=war|slots=12",
    "500|anchor|id=w10|kind=home|team=allies|x=-1500|y=0|z=0",
    "500|anchor|id=w90|kind=home|team=axis|x=1700|y=100|z=0",
    "500|anchor|id=w41|kind=camp|team=none|x=200|y=400|z=0",
    "1000|join|pn=0|p=marcus|pt=allies|pb=0",
    "1000|join|pn=1|p=bot1|pt=axis|pb=1",
    "1000|join|pn=2|p=bot2|pt=axis|pb=1",
    "5000|snap|allies=300|axis=200|humans=1|bots=2",
    "5000|p|pn=0|p=marcus|pt=allies|pb=0|k=9|d=2|s=900|alive=1",
    "5000|p|pn=1|p=bot1|pt=axis|pb=1|k=1|d=4|s=100|alive=1|skill=3|camp=5|sprint=60|goal=0",
    "5000|p|pn=2|p=bot2|pt=axis|pb=1|k=1|d=5|s=100|alive=1|skill=3|camp=5|sprint=60|goal=0",
]


def json_dump(value: object) -> str:
    return json.dumps(value)


@pytest.fixture
def match_state() -> MatchState:
    return lines_to_state(MATCH_LINES)


@pytest.fixture
def tmp_scriptdata(tmp_path: Path) -> Path:
    directory = tmp_path / "scriptdata" / "shotcaller"
    directory.mkdir(parents=True)
    return directory
