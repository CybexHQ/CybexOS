#!/usr/bin/env python3
"""Omarchy packages in the managed shell of a disposable installed QA guest.

Run after settings-runtime.py --prepare. The same guest/account/marker guard
applies. Upstream fixtures stay unchanged; generated fixtures exercise the
remaining host contracts. This does not qualify external plugin dependencies.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('settings_runtime', ROOT/'tests/settings-runtime.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def exercise(audit):
    fixtures = ROOT/'tests/omarchy-plugins'
    home = Path('/home/cybexqa')
    preferences = home/'.config/cybexos/plugins.json'
    original = preferences.read_bytes() if preferences.exists() else None
    installed = home/'.local/share/cybexos/plugins'
    ids = []

    def cli(*args):
        reply = audit.user(['cybex', 'plugin', *args], timeout=60)
        audit.wait('!UserPlugins.busy')
        return reply

    def widget(plugin):
        return 'UserPlugins.widgetHosts.find(h => h.descriptor.id === '+json.dumps(plugin)+' && h.ready).widget'

    def entry(plugin, kind):
        return 'OmarchyPlugins.records['+json.dumps(plugin+':'+kind)+']?.host?.instance'

    def own(directory):
        for path in [directory, *directory.rglob('*')]:
            if not path.is_symlink():
                os.chown(path, 1000, 100)

    with tempfile.TemporaryDirectory(prefix='omarchy-installed-', dir=home) as temporary:
        base = Path(temporary)
        own(base)

        def package(plugin, folder=None, manifest=None):
            assert not (installed/plugin).exists(), 'Refusing to replace an existing package: '+plugin
            target = base/plugin
            if folder:
                shutil.copytree(fixtures/folder, target)
            else:
                target.mkdir()
                shutil.copyfile(fixtures/'Spacer.qml', target/'Spacer.qml')
            if manifest:
                (target/'manifest.json').write_text(json.dumps(manifest))
            own(target)
            audit.user(['git','init',str(target)])
            audit.user(['git','-C',str(target),'add','.'])
            audit.user(['git','-C',str(target),'-c','user.name=Cybex OS QA',
                        '-c','user.email=qa@example.invalid','commit','-m','Pinned runtime fixture'])
            cli('add', str(target))
            ids.append(plugin)

        try:
            package('markbusking.pomodoro', 'pomodoro')
            package('omarchy.media', 'media')
            package('omarchy.bar', 'bar')
            package('audit.omarchy.spacer', manifest={
                'schemaVersion':1,'id':'audit.omarchy.spacer','name':'QA spacer','version':'1',
                'kinds':['bar-widget'],'entryPoints':{'barWidget':'Spacer.qml'},
                'barWidget':{'allowMultiple':True,'defaults':{'size':12}}})
            for plugin, kinds in [('audit.omarchy.bundle',['service','panel','bar-widget']),
                                  ('audit.omarchy.overlay',['overlay']),
                                  ('audit.omarchy.menu',['menu'])]:
                entries = {kind: 'Entry.qml' for kind in kinds}
                if 'service' in kinds:
                    entries['service'] = 'Service.qml'
                if 'bar-widget' in kinds:
                    del entries['bar-widget']
                    entries['barWidget'] = 'Widget.qml'
                package(plugin, 'contract', {'schemaVersion':1,'id':plugin,'name':plugin,'version':'1',
                    'kinds':kinds,'entryPoints':entries,'keepLoaded':plugin.endswith('bundle'),
                    'barWidget':{'allowMultiple':'bar-widget' in kinds}})
            protected = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                         for plugin in ids for path in (installed/plugin).rglob('*')
                         if path.is_file() and '.git' not in path.parts}
            for plugin in ids:
                if plugin != 'omarchy.bar':
                    cli('enable',plugin,'--section','left','--width','70')
            cli('set','markbusking.pomodoro','sound','false')
            cli('set','markbusking.pomodoro','workMinutes','2')
            audit.wait('UserPlugins.widgetHosts.some(h => h.descriptor.id === "markbusking.pomodoro" && h.ready)')
            pomodoro = widget('markbusking.pomodoro')
            audit.wait(pomodoro+'.workMinutes === 2 && !'+pomodoro+'.soundEnabled')
            audit.evaluate(pomodoro+'.toggleTimer()')
            audit.wait(pomodoro+'.running && '+pomodoro+'.remainingSeconds < 120',timeout=10)
            audit.evaluate(pomodoro+'.toggleTimer()')
            paused = audit.evaluate(pomodoro+'.remainingSeconds')
            time.sleep(1.2)
            assert audit.evaluate(pomodoro+'.remainingSeconds') == paused
            audit.evaluate(pomodoro+'.resetPhase()')
            audit.wait(pomodoro+'.remainingSeconds === 120')
            audit.wait('OmarchyPlugins.serviceFor("omarchy.media") !== null')
            audit.wait('UserPlugins.widgetHosts.some(h => h.descriptor.id === "omarchy.media" && h.ready)')
            assert audit.evaluate(widget('omarchy.media')+'.mediaService !== null')

            cli('instance','audit.omarchy.spacer','one','--section','left','--width','30')
            cli('instance','audit.omarchy.spacer','two','--section','right','--width','40')
            cli('set','audit.omarchy.spacer','size','23','--instance','one')
            cli('set','audit.omarchy.spacer','size','37','--instance','two')
            audit.wait('UserPlugins.widgetHosts.filter(h => h.descriptor.id === "audit.omarchy.spacer" && h.ready).length === 2')
            audit.wait('JSON.stringify(UserPlugins.widgetHosts.filter(h => h.descriptor.id === "audit.omarchy.spacer" && h.ready).map(h=>h.widget.span).sort()) === "[23,37]"')
            spans = audit.evaluate('UserPlugins.widgetHosts.filter(h => h.descriptor.id === "audit.omarchy.spacer" && h.ready).map(h=>h.widget.span).sort()')
            assert spans == [23,37], spans

            audit.wait('OmarchyPlugins.serviceFor("audit.omarchy.bundle") !== null')
            audit.wait('UserPlugins.widgetHosts.some(h => h.descriptor.id === "audit.omarchy.bundle" && h.ready)')
            assert audit.evaluate(widget('audit.omarchy.bundle')+'.shared === OmarchyPlugins.serviceFor("audit.omarchy.bundle")')
            for plugin, kind in [('audit.omarchy.bundle','panel'),('audit.omarchy.overlay','overlay'),('audit.omarchy.menu','menu')]:
                audit.evaluate('OmarchyPlugins.summon('+json.dumps(plugin)+', "qa-payload")')
                audit.wait(entry(plugin,kind)+'?.opened')
                assert audit.evaluate(entry(plugin,kind)+'.received[0]') == 'qa-payload'
                audit.evaluate('OmarchyPlugins.hide('+json.dumps(plugin)+')')
            cli('bar','omarchy.bar')
            audit.wait('OmarchyPlugins.replacementActive')
            cli('bar','native')
            audit.wait('!OmarchyPlugins.replacementActive')
            audit.wait('UserPlugins.widgetHosts.some(h => h.descriptor.id === "markbusking.pomodoro" && h.ready)')
            assert audit.evaluate('Object.keys(OmarchyPlugins.errors)') == []
            assert not audit.evaluate('UserPlugins.error')
            for path, digest in protected.items():
                assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest, path
            return {'upstreamPomodoroTimer':True,'independentSpacerInstances':True,
                    'upstreamMediaServiceAndNativeWidget':True,'serviceInjection':True,
                    'panelOverlayMenuPayloads':True,'upstreamReplacementAndNativeRestore':True,
                    'installedPackagesUnmodified':True,
                    'mediaPlayback':'not exercised without a real MPRIS player'}
        finally:
            cli('bar','native')
            for plugin in reversed(ids):
                cli('disable',plugin)
                cli('remove',plugin)
            if original is None:
                preferences.unlink(missing_ok=True)
            else:
                pending = preferences.with_suffix('.qa-restore')
                pending.write_bytes(original)
                os.chown(pending,1000,100)
                pending.chmod(0o600)
                pending.replace(preferences)
            cli('reload')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report',type=Path,required=True)
    args=parser.parse_args()
    audit=MODULE.Audit(args.report)
    audit.test('one managed shell before Omarchy runtime audit',audit.guard)
    audit.test('Omarchy packages in installed Hyprland',lambda:exercise(audit))
    audit.test('one managed shell after Omarchy runtime audit',audit.guard)
    raise SystemExit(1 if any(test['result']=='failed' for test in audit.report['tests']) else 0)


if __name__ == '__main__':
    main()
