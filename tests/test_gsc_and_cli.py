from __future__ import annotations

import re
from pathlib import Path

import pytest

from shotcaller.cli import main

GSC_ROOT = Path(__file__).resolve().parent.parent / "gsc"
GSC_FILES = sorted(GSC_ROOT.rglob("*.gsc"))


def test_there_are_gsc_files():
    assert len(GSC_FILES) >= 6


@pytest.mark.parametrize("path", GSC_FILES, ids=lambda p: p.name)
def test_gsc_braces_and_parentheses_balance(path):
    code = "\n".join(line for line in path.read_text().splitlines() if not line.lstrip().startswith("//"))
    code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', code)
    assert code.count("{") == code.count("}")
    assert code.count("(") == code.count(")")
    assert code.count("[") == code.count("]")


@pytest.mark.parametrize("path", GSC_FILES, ids=lambda p: p.name)
def test_gsc_has_no_inline_comments(path):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        stripped = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
        code, sep, _ = stripped.partition("//")
        assert not (sep and code.strip()), f"{path.name}:{number} has an inline comment"


@pytest.mark.parametrize("path", GSC_FILES, ids=lambda p: p.name)
def test_every_gsc_function_has_a_doc_comment(path):
    lines = path.read_text().splitlines()
    for index, line in enumerate(lines):
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*\(.*\)$", line) and index + 1 < len(lines) and lines[index + 1] == "{":
            if path.name == "shotcaller.gsc":
                continue
            assert lines[index - 1].startswith("///"), f"{path.name}:{index + 1} {line} lacks a /// doc comment"


def test_cli_version(capsys):
    with pytest.raises(SystemExit) as exit_info:
        main(["--version"])
    assert exit_info.value.code == 0
    assert capsys.readouterr().out.startswith("shotcaller ")


def test_example_config_loads_and_fills_defaults(tmp_path):
    from shotcaller.config import load

    example = Path(__file__).resolve().parent.parent / "examples" / "shotcaller.toml"
    config = load(example)
    assert config.llm.timeouts_s["squad"] == 25.0 and config.llm.max_tokens["chat"] == 200
    assert config.limits.maps[0] == "mp_rust" and config.gating.thresholds["squad"] == 0.95

    partial = tmp_path / "partial.toml"
    partial.write_text('[server]\ngame_dir = "/g"\n[llm.timeouts_s]\nsquad = 5.0\n[gating.thresholds]\nchat = 0.1\n')
    config = load(partial)
    assert config.llm.timeouts_s == {"match": 30.0, "squad": 5.0, "chat": 8.0}
    assert config.gating.thresholds == {"match": 0.9, "squad": 0.95, "chat": 0.1}
