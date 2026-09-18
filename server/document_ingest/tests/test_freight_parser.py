from aims_docintel.freight_parser import FreightOrderParser


def test_parses_load_unload_order():
    raw = """
Transport Order
Reference: CADDY-260918-4412
Customer: Example Logistics GmbH

LOAD 1
ACME Kft.
9027 Győr, Ipari park 12.
18.09.2026
09:30-10:30
+36 30 111 2233

UNLOAD 1
Example s.r.o.
602 00 Brno, Prumyslova 8
18.09.2026
14:00-16:00

Goods: machine parts
1 pallet
112 kg
Vehicle type: van
"""
    order = FreightOrderParser().parse(raw)
    assert order.reference == "CADDY-260918-4412"
    assert order.customer == "Example Logistics GmbH"
    assert len(order.pickups) == 1
    assert len(order.deliveries) == 1
    assert "Győr" in (order.pickups[0].address or "")
    assert "Brno" in (order.deliveries[0].address or "")
    assert order.pallets == 1
    assert order.weight_kg == 112
    assert order.vehicle_requirement == "van"
    assert order.to_driver_payload()["reference"] == "CADDY-260918-4412"


def test_parses_hungarian_order():
    raw = """
Fuvarmegbízás száma: AIMS-778899
Megrendelő: Teszt Kft.
Felrakó:
Logistic-A.I.M.S. Kft.
2900 Komárom, Minta utca 1.
2026-09-18 08:00
Lerakóhely:
Minta GmbH
10115 Berlin, Beispielstrasse 20.
2026-09-19 09:00-11:00
Áru: autóalkatrész
2 raklap
900 kg
Járműigény: dobozos furgon
"""
    order = FreightOrderParser().parse(raw)
    assert order.reference == "AIMS-778899"
    assert order.customer == "Teszt Kft."
    assert len(order.pickups) == 1
    assert len(order.deliveries) == 1
    assert order.pallets == 2
    assert order.weight_kg == 900
    assert "furgon" in (order.vehicle_requirement or "")


def test_unknown_layout_stays_reviewable_instead_of_guessing():
    raw = """
ABC Transport
Some random text without route labels.
Cargo 500 kg.
"""
    order = FreightOrderParser().parse(raw)
    assert order.requires_review is True
    assert order.pickups == []
    assert order.deliveries == []
    assert any("ellenőrzést" in item for item in order.warnings)
