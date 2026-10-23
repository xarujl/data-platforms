#!/usr/bin/env python3
"""Copy the cluster XML files, setting Java 11 for Hive's MR containers."""
import pathlib
import sys
import xml.etree.ElementTree as ET

source, target, java_home = map(pathlib.Path, sys.argv[1:])
changed = False
for name in ('core-site', 'hdfs-site', 'yarn-site', 'mapred-site'):
    content = (source / (name + '.xml')).read_bytes()
    if name == 'mapred-site':
        root = ET.fromstring(content)
        keys = ('yarn.app.mapreduce.am.env', 'mapreduce.map.env', 'mapreduce.reduce.env')
        for prop in list(root.findall('property')):
            if prop.findtext('name') in keys:
                root.remove(prop)
        for key in keys:
            prop = ET.SubElement(root, 'property')
            ET.SubElement(prop, 'name').text = key
            ET.SubElement(prop, 'value').text = f'JAVA_HOME={java_home},HADOOP_CONF_DIR={source}'
        content = ET.tostring(root, encoding='utf-8', xml_declaration=True)
    destination = target / (name + '.xml')
    if not destination.exists() or destination.read_bytes() != content:
        destination.write_bytes(content)
        destination.chmod(0o640)
        changed = True
print('changed' if changed else 'unchanged')
