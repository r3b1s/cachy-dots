#!/usr/bin/env python3
"""Render the stack's Incus objects from stack.toml and services/*/service.toml.

Usage: render.py STACK_DIR EDGE_IP OUT_DIR

Writes, as JSON (which Incus reads as YAML):
  OUT_DIR/networks/<name>.json   a bridge per service
  OUT_DIR/acls/<name>.json       the bridge's ACL
  OUT_DIR/profiles/<name>.json   the instance's limits, NIC, disk and (edge) proxy devices
  OUT_DIR/instances.tsv          name, type, profile, service
  OUT_DIR/sites.tsv              port, upstream address (the edge's routes, for checks)

Incus evaluates an ACL's reject rules before its allow rules, so "reject private,
allow this one private host" cannot be written. Each ACL instead rejects by
default and allows the public IPv4 space (everything minus stack.toml's
`private` list) plus each exception.
"""
import ipaddress
import json
import sys
import tomllib
from pathlib import Path


def die(msg):
    sys.exit(f"render.py: {msg}")


def public_ranges(private):
    nets = [ipaddress.ip_network("0.0.0.0/0")]
    for p in map(ipaddress.ip_network, private):
        rest = []
        for n in nets:
            if p.subnet_of(n):
                rest.extend(n.address_exclude(p))
            elif not n.subnet_of(p):
                rest.append(n)
        nets = rest
    return sorted(ipaddress.collapse_addresses(nets))


def rule(destination=None, source=None, protocol=None, port=None, description=None):
    r = {"action": "allow", "state": "enabled"}
    if destination:
        r["destination"] = destination
    if source:
        r["source"] = source
    if protocol:
        r["protocol"] = protocol
    if port:
        r["destination_port"] = str(port)
    if description:
        r["description"] = description
    return r


def parse_allow(entry):
    """"100.92.3.4/32 tcp 8080" -> rule; protocol and port are optional."""
    parts = entry.split()
    if not 1 <= len(parts) <= 3:
        die(f"bad egress entry {entry!r}: want 'CIDR [tcp|udp [PORT]]'")
    ipaddress.ip_network(parts[0])
    return rule(parts[0], protocol=parts[1] if len(parts) > 1 else None,
                port=parts[2] if len(parts) > 2 else None, description=entry)


def main():
    if len(sys.argv) != 4:
        die("usage: render.py STACK_DIR EDGE_IP OUT_DIR")
    root, edge_ip, out = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
    ipaddress.IPv4Address(edge_ip)
    stack = tomllib.loads((root / "stack.toml").read_text())
    prefix, first, last = stack["prefix"], stack["ports"]["first"], stack["ports"]["last"]

    svcs = {}
    for f in sorted(root.glob("services/*/service.toml")):
        s = tomllib.loads(f.read_text())
        s["name"] = f.parent.name
        svcs[s["name"]] = s
    if "edge" not in svcs:
        die("services/edge is missing")
    seen = {}
    for s in svcs.values():
        i = s["index"]
        if i in seen:
            die(f"{s['name']} and {seen[i]} share index {i}")
        seen[i] = s["name"]
        if not 0 <= i <= 255 or first + i > last:
            die(f"{s['name']}: index {i} is outside the address plan or the port block {first}-{last}")
        if s["type"] not in ("container", "virtual-machine"):
            die(f"{s['name']}: type is container or virtual-machine")
        if len(f"{prefix}-{s['name']}") > 15:
            die(f"{prefix}-{s['name']}: bridge names are at most 15 characters")
        s["host"] = f"{stack['subnet']}.{i}.1"
        s["guest"] = f"{stack['subnet']}.{i}.2"
        s["port"] = first + i if "edge" in s else None

    edge = svcs["edge"]
    public = ",".join(map(str, public_ranges(stack["private"])))
    for d in ("networks", "acls", "profiles"):
        (out / d).mkdir(parents=True, exist_ok=True)
    instances, sites = [], []

    for s in svcs.values():
        name = f"{prefix}-{s['name']}"
        egress = [rule(public, description="the public internet")]
        ingress = []
        for entry in s.get("egress", {}).get("allow", []):
            egress.append(parse_allow(entry))
        for used in s.get("egress", {}).get("uses", []):
            if used not in svcs or svcs[used]["port"] is None:
                die(f"{s['name']} uses {used}, which the edge does not publish")
            # Incus's NAT proxy rewrites <NetBird address>:<port> to the edge
            # before the ACL sees the packet, so the rule names the edge.
            egress.append(rule(f"{edge['guest']}/32", protocol="tcp", port=svcs[used]["port"],
                               description=f"{used}, through the edge"))
        if s is edge:
            for t in svcs.values():
                if t["port"] is not None:
                    ingress.append(rule(protocol="tcp", port=t["port"], description=f"{t['name']} (published)"))
                    egress.append(rule(f"{t['guest']}/32", protocol="tcp", port=t["edge"]["upstream"],
                                       description=f"{t['name']} (upstream)"))
                    sites.append(f"{t['port']}\t{t['guest']}:{t['edge']['upstream']}\t{t['name']}")
        elif s["port"] is not None:
            ingress.append(rule(source=f"{edge['guest']}/32", protocol="tcp", port=s["edge"]["upstream"],
                                description="the edge"))

        inbound = "its published ports" if s is edge else "the edge" if s["port"] is not None else "nothing"
        acl = {"description": f"{s['name']}: out to the public internet and its exceptions; in from {inbound}",
               "egress": egress, "ingress": ingress}
        net = {"description": f"{s['name']}'s bridge: the host .1, the guest .2", "config": {
            "ipv4.address": f"{s['host']}/24",
            "ipv4.nat": "true",
            "ipv6.address": "none",
            "security.acls": name,
            "security.acls.default.egress.action": "reject",
            "security.acls.default.ingress.action": "reject",
        }}
        devices = {
            "eth0": {"type": "nic", "network": name, "ipv4.address": s["guest"]},
            "root": {"type": "disk", "path": "/", "pool": "default", "size": s["disk"]},
        }
        if s is edge:
            for t in svcs.values():
                if t["port"] is not None:
                    devices[f"pub-{t['name']}"] = {
                        "type": "proxy", "nat": "true",
                        "listen": f"tcp:{edge_ip}:{t['port']}",
                        "connect": f"tcp:{edge['guest']}:{t['port']}",
                    }
        config = {"limits.cpu": str(s["cpus"]), "limits.memory": s["memory"], "boot.autostart": "true"}
        if s["type"] == "virtual-machine":
            config["security.secureboot"] = "false"
        else:
            # Nix builds in a sandbox of nested namespaces.
            config["security.nesting"] = "true"
        profile = {"description": f"{s['name']}: limits, NIC and disk", "config": config, "devices": devices}

        for d, doc in (("networks", net), ("acls", acl), ("profiles", profile)):
            (out / d / f"{name}.json").write_text(json.dumps(doc, indent=2) + "\n")
        instances.append(f"{name}\t{s['type']}\t{name}\t{s['name']}")

    (out / "instances.tsv").write_text("".join(f"{l}\n" for l in instances))
    (out / "sites.tsv").write_text("".join(f"{l}\n" for l in sites))


main()
