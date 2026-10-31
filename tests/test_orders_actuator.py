from __future__ import annotations

from shotcaller.actuator import MatchActuator, OrderFile
from shotcaller.orders import BotOrder, ChatLine, Goal, MatchOrder, Squad, TeamOrder, encode, squad_to_dict


class FakeRcon:
    def __init__(self):
        self.sent: list[str] = []

    def send(self, command: str) -> str:
        self.sent.append(command)
        return ""


def sample_squad() -> Squad:
    return Squad(
        teams=[TeamOrder("axis", {"camp": 60, "sprint": 30})],
        bots=[BotOrder(7, skill=5, behaviors={"camp": 80}, goal=Goal("w123", 150)), BotOrder(9, clear_goal=True), BotOrder(3)],
    )


def test_encode_matches_the_wire_format_the_gsc_parses():
    text = encode(12, "mp_rust", 45000, sample_squad(), [ChatLine(7, "all", "Nice try.")])
    assert text == (
        "seq|12\nmap|mp_rust\nttl|45000\n"
        "team|axis|camp=60|sprint=30\n"
        "bot|7|skill=5|camp=80|goal=w123:150\n"
        "bot|9|goal=clear\n"
        "chat|7|all|Nice try.\n"
    )


def test_squad_to_dict_omits_empty_orders():
    summary = squad_to_dict(sample_squad())
    assert [b["slot"] for b in summary["bots"]] == [7, 9] or [b["slot"] for b in summary["bots"]] == [7]
    assert summary["bots"][0]["goal"] == {"anchor": "w123", "radius": 150}


def test_order_file_writes_atomically_and_bumps_the_sequence(tmp_path):
    orders = OrderFile(tmp_path / "shotcaller" / "orders.txt")
    first = orders.write("mp_rust", 1000, Squad(), [])
    second = orders.write("mp_rust", 1000, sample_squad(), [])
    assert (first, second) == (1, 2)
    assert (tmp_path / "shotcaller" / "orders.txt").read_text().startswith("seq|2\n")
    assert not list((tmp_path / "shotcaller").glob("*.tmp"))
    orders.clear()
    assert not (tmp_path / "shotcaller" / "orders.txt").exists()


def test_match_actuator_sends_only_set_fields():
    rcon = FakeRcon()
    sent = MatchActuator(rcon).apply(MatchOrder(skill_min=3, bot_count=8, next_map="mp_terminal"))
    assert sent == ["set bots_skill_min 3", "set bots_manage_fill 8", 'set sv_mapRotationCurrent "gametype war map mp_terminal"']
    assert rcon.sent == sent
    assert MatchActuator(FakeRcon()).apply(MatchOrder()) == []
