#!/usr/bin/env python3
import argparse
import itertools
import subprocess
import sys
import re
import yaml  # pip install pyyaml

def parse_topology(yaml_file):
    """
    Lit le Docker-Compose YAML et retourne :
     - nodes : liste des noms internes de services
     - labels: dict mapping nom interne -> label plus lisible
     - nets  : dict mapping réseau -> liste de services
     - links : liste de tuples (svc1, svc2, network)
    """
    with open(yaml_file, 'r') as f:
        data = yaml.safe_load(f)

    services = data.get('services', {})
    nodes = list(services.keys())

    # Prépare labels lisibles
    labels = {}
    for svc_name, svc_conf in services.items():
        host = svc_conf.get('hostname')
        labels[svc_name] = host if host else re.sub(r"-[0-9a-f]{8}-.*$", '', svc_name)

    # Regroupe services par réseau
    nets = {}
    for svc_name, svc_conf in services.items():
        for net in svc_conf.get('networks', []):
            nets.setdefault(net, []).append(svc_name)

    # Génère liens (combinaisons de paires)
    links = []
    for net_name, members in nets.items():
        for a, b in itertools.combinations(members, 2):
            links.append((a, b, net_name))

    return nodes, labels, nets, links

def write_dot(nodes, labels, nets, links, dot_file, engine, directed):
    kind = 'digraph' if directed else 'graph'
    connector = '->' if directed else '--'
    with open(dot_file, 'w') as f:
        f.write(f'{kind} topology {{\n')
        f.write('  rankdir=LR;\n')
        f.write('  overlap=false;\n')
        f.write('  splines=true;\n')
        f.write('  node [shape=circle, style=filled, fillcolor=lightgrey, fontsize=10];\n')
        f.write(f'  layout={engine};\n')

        for svc in nodes:
            lbl = labels.get(svc, svc)
            f.write(f'  "{svc}" [label="{lbl}"];\n')

        for a, b, net in links:
            f.write(f'  "{a}" {connector} "{b}" [label="{net}", fontsize=8];\n')

        for net_name, members in nets.items():
            f.write(f'  subgraph cluster_{net_name.replace("-", "_")} {{\n')
            f.write(f'    label = "{net_name}";\n')
            f.write('    style = dashed;\n')
            for svc in members:
                f.write(f'    "{svc}";\n')
            f.write('  }\n')

        f.write('}\n')
    print(f'Written Graphviz dot file: {dot_file}')

def generate_image(dot_file, out_file, fmt, engine):
    try:
        subprocess.run([engine, f'-T{fmt}', dot_file, '-o', out_file], check=True)
        print(f'Generated {fmt.upper()} image: {out_file}')
    except FileNotFoundError:
        print(f'Error: `{engine}` not found. Installez Graphviz et ajoutez `{engine}` au PATH.', file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f'Error generating {fmt}: {e}', file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(
        description='Convert Docker-Compose YAML to Graphviz (dot + image)')
    parser.add_argument('-i', '--input', required=True,
                        help='Fichier YAML d’entrée (ex: topology.yaml)')
    parser.add_argument('-d', '--dot', required=True,
                        help='Fichier .dot de sortie (ex: topology.dot)')
    parser.add_argument('-f', '--format', choices=['png','svg','pdf','jpg'], default='svg',
                        help='Format de sortie (png, svg, pdf, jpg).')
    parser.add_argument('-e', '--engine', choices=['dot','neato','fdp','sfdp','circo'], default='dot',
                        help='Moteur Graphviz à utiliser pour le layout.')
    parser.add_argument('--directed', action='store_true',
                        help='Générer un graphe dirigé (avec flèches). Sinon graph non-dirigé.')
    args = parser.parse_args()

    nodes, labels, nets, links = parse_topology(args.input)
    write_dot(nodes, labels, nets, links, args.dot, args.engine, args.directed)

    img_file = re.sub(r'\.[^.]+$', f'.{args.format}', args.dot)
    generate_image(args.dot, img_file, args.format, args.engine)

if __name__ == '__main__':
    main()
