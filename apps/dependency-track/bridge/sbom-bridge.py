#!/usr/bin/env python3
"""Exporte les SbomReport de Trivy Operator vers Dependency-Track.

Le CR `SbomReport` contient dans `.report.components` un document CycloneDX
complet (bomFormat/specVersion/components). On l'envoie tel quel a l'API
`PUT /api/v1/bom` avec `autoCreate: true`.

Un ConfigMap `sbom-bridge-state` garde la resourceVersion du dernier rapport
uploade par UID : les runs suivants ne renvoient que les BOM modifies.
Aucune dependance externe (uniquement la stdlib Python) : l'image peut rester
minimale et etre pinnée par digest.
"""

import base64
import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

K8S_HOST = os.environ["KUBERNETES_SERVICE_HOST"]
K8S_PORT = os.environ["KUBERNETES_SERVICE_PORT"]
NAMESPACE = os.environ["POD_NAMESPACE"]
CLUSTER = os.environ.get("CLUSTER_NAME", "k8s-shared")
DT_URL = os.environ.get(
    "DT_URL", "http://dependency-track-api-server.dependency-track.svc.cluster.local:8080"
)
TOKEN_PATH = "/var/run/secrets/dt/token"
STATE_CM = "sbom-bridge-state"
STATE_KEY = "uploaded"

with open("/var/run/secrets/kubernetes.io/serviceaccount/token", encoding="utf-8") as f:
    SA_TOKEN = f.read().strip()

SSL_CTX = ssl.create_default_context(cafile="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")


def k8s(method, path, body=None, content_type="application/json"):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": "Bearer " + SA_TOKEN}
    if data is not None:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(
        f"https://{K8S_HOST}:{K8S_PORT}{path}", data=data, headers=headers, method=method
    )
    with urllib.request.urlopen(req, context=SSL_CTX, timeout=30) as resp:
        raw = resp.read().decode()
        return json.loads(raw) if raw else None


def list_sbom_reports():
    """Liste tous les SbomReport du cluster, en suivant les pages `continue`."""
    reports, cont = [], None
    while True:
        path = "/apis/aquasecurity.github.io/v1alpha1/sbomreports"
        if cont:
            path += "?continue=" + urllib.parse.quote(cont)
        page = k8s("GET", path)
        reports.extend(page.get("items", []))
        cont = page.get("metadata", {}).get("continue")
        if not cont:
            return reports


def load_state():
    try:
        cm = k8s("GET", f"/api/v1/namespaces/{NAMESPACE}/configmaps/{STATE_CM}")
        return json.loads(cm.get("data", {}).get(STATE_KEY, "{}"))
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return {}
        raise


def save_state(state):
    cm = {
        "apiVersion": "v1",
        "kind": "ConfigMap",
        "metadata": {"name": STATE_CM, "namespace": NAMESPACE},
        "data": {STATE_KEY: json.dumps(state, sort_keys=True)},
    }
    path = f"/api/v1/namespaces/{NAMESPACE}/configmaps/{STATE_CM}"
    try:
        k8s("PUT", path, body=cm)
    except urllib.error.HTTPError as exc:
        if exc.code != 404:
            raise
        k8s("POST", f"/api/v1/namespaces/{NAMESPACE}/configmaps", body=cm)


def upload_bom(api_key, project_name, project_version, bom):
    payload = {
        "projectName": project_name,
        "projectVersion": project_version,
        "autoCreate": True,
        "bom": base64.b64encode(json.dumps(bom).encode()).decode(),
    }
    req = urllib.request.Request(
        f"{DT_URL}/api/v1/bom",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "X-Api-Key": api_key},
        method="PUT",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        # Reponse 200 : {"token": "..."} ; on ne bloque pas sur le traitement
        # asynchrone de l'analyse, Dependency-Track le fait en tache de fond.
        return resp.status


def main():
    if not os.path.isfile(TOKEN_PATH):
        print("ERREUR: cle API Dependency-Track absente. Creer la cle dans DT "
              "et ecrire son token dans Vault (voir README.md).", file=sys.stderr)
        return 2
    with open(TOKEN_PATH, encoding="utf-8") as f:
        api_key = f.read().strip()
    if not api_key:
        print("ERREUR: cle API Dependency-Track vide.", file=sys.stderr)
        return 2

    state = load_state()
    reports = list_sbom_reports()
    print(f"{len(reports)} SbomReport trouves, {len(state)} deja uploades.")

    uploaded, skipped, failed = 0, 0, 0
    for report in reports:
        meta = report.get("metadata", {})
        bom = report.get("report", {}).get("components")
        if not isinstance(bom, dict) or "bomFormat" not in bom:
            continue

        uid = meta.get("uid")
        rv = meta.get("resourceVersion", "")
        if not uid:
            continue
        fingerprint = f"{rv}/{report.get('report', {}).get('artifact', {}).get('digest', '')}"
        if state.get(uid) == fingerprint:
            skipped += 1
            continue

        labels = meta.get("labels", {})
        ns = labels.get("trivy-operator.resource.namespace", meta.get("namespace", "unknown"))
        workload = labels.get("trivy-operator.resource.name", meta.get("name", "unknown"))
        container = labels.get("trivy-operator.container.name", "default")
        digest = report.get("report", {}).get("artifact", {}).get("digest", "") or ""
        version = digest.split(":")[-1][:12] if digest else rv

        project = f"{CLUSTER}/{ns}/{workload}/{container}"
        try:
            status = upload_bom(api_key, project, version, bom)
            if status != 200:
                raise RuntimeError(f"HTTP {status}")
            state[uid] = fingerprint
            uploaded += 1
        except Exception as exc:  # noqa: BLE001 - on continue avec les autres rapports
            failed += 1
            print(f"ERREUR upload {project}@{version}: {exc}", file=sys.stderr)

    if uploaded or skipped:
        try:
            save_state(state)
        except Exception as exc:  # noqa: BLE001
            print(f"ERREUR sauvegarde etat: {exc} -- les BOM seront re-uploades.", file=sys.stderr)

    print(f"Termine: {uploaded} uploades, {skipped} inchanges, {failed} en echec.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
