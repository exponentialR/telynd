"""Adversarial release provenance and archive tests; no Apple credentials."""
import contextlib
import importlib.util
import os
from pathlib import Path
import plistlib
import stat
import struct
import subprocess
import tempfile
import unittest
from unittest import mock
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT/'scripts'/f'{name}.py')
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result)
    return result

PROVENANCE = module('release_provenance')
ARTIFACT = module('prepare_release_input')

@contextlib.contextmanager
def repository():
    with tempfile.TemporaryDirectory() as folder:
        previous = os.getcwd(); os.chdir(folder)
        try:
            def git(*args):
                return subprocess.check_output(['git', *args], stderr=subprocess.DEVNULL, text=True).strip()
            git('init','-b','main'); git('config','user.name','Release Fixture'); git('config','user.email','fixture@example.test')
            yield Path(folder), git
        finally:
            os.chdir(previous)


def rules():
    main = {'target':'branch','enforcement':'active','bypass_actors':[], 'conditions':{'ref_name':{'include':['refs/heads/main'],'exclude':[]}},'rules':[
        {'type':'pull_request','parameters':{'required_approving_review_count':1,'dismiss_stale_reviews_on_push':True}},
        {'type':'required_status_checks','parameters':{'strict_required_status_checks_policy':True,'required_status_checks':[{'context':'mac-app'},{'context':'recovery'},{'context':'windows-recovery'}]}}]}
    tag = {'target':'tag','enforcement':'active','bypass_actors':[], 'conditions':{'ref_name':{'include':['refs/tags/v*'],'exclude':[]}},'rules':[{'type':'update'},{'type':'deletion'}]}
    return main, tag

class ProvenanceTest(unittest.TestCase):
    def test_off_main_tag_is_rejected_even_though_tag_equality_passes(self):
        with repository() as (root, git):
            (root/'source').write_text('approved'); git('add','.'); git('commit','-m','approved'); approved = git('rev-parse','HEAD')
            git('checkout','--orphan','unreviewed'); (root/'source').write_text('outside main'); git('add','.'); git('commit','-m','unreviewed'); git('tag','v0.2.0')
            self.assertEqual(git('rev-parse','HEAD'),git('rev-parse','refs/tags/v0.2.0^{commit}'))
            with self.assertRaisesRegex(PROVENANCE.PolicyError,'outside'):
                PROVENANCE.resolve('v0.2.0', approved)

    def test_approved_annotated_tag_and_moved_tag(self):
        with repository() as (root, git):
            (root/'source').write_text('approved');git('add','.');git('commit','-m','approved');approved=git('rev-parse','HEAD')
            git('tag','-a','v0.2.0','-m','version'); result=PROVENANCE.resolve('v0.2.0',approved)
            self.assertEqual(result['revision'],approved)
            git('tag','-f','v0.2.0',approved)
            with self.assertRaisesRegex(PROVENANCE.PolicyError,'tag object changed'):
                PROVENANCE.resolve('v0.2.0',approved,**{'expected_tag_object':result['tag_object']})
            with self.assertRaises(PROVENANCE.PolicyError): PROVENANCE.resolve('../main',approved)

    def test_protection_requires_review_checks_and_immutable_tags(self):
        main, tag=rules();PROVENANCE.validate_rules(main,tag)
        for kind in ['disabled','excluded','bypass','mutable','unreviewed','checks']:
            main,tag=rules()
            if kind=='disabled': tag['enforcement']='evaluate'
            if kind=='excluded': tag['conditions']['ref_name']['exclude']=['refs/tags/v0.2.0']
            if kind=='bypass': main['bypass_actors']=[{'actor_type':'Team'}]
            if kind=='mutable': tag['rules']=[{'type':'deletion'}]
            if kind=='unreviewed': main['rules'][0]['parameters']['required_approving_review_count']=0
            if kind=='checks': main['rules'][1]['parameters']['required_status_checks']=[]
            with self.subTest(kind=kind), self.assertRaises(PROVENANCE.PolicyError): PROVENANCE.validate_rules(main,tag)

    def test_missing_policy_and_wrong_dispatch_context_fail_before_api(self):
        env={'GITHUB_REPOSITORY':'example/repo','GITHUB_REF':'refs/heads/feature','GITHUB_SHA':'a'*40,'GITHUB_EVENT_NAME':'workflow_dispatch'}
        with mock.patch.dict(os.environ,env),mock.patch.object(PROVENANCE,'api') as api:
            with self.assertRaises(PROVENANCE.PolicyError): PROVENANCE.github_policy('v0.2.0','a'*40,{},'1','2')
            os.environ['GITHUB_REF']='refs/heads/main'
            with self.assertRaises(PROVENANCE.PolicyError): PROVENANCE.github_policy('v0.2.0','a'*40,{},None,None)
            api.assert_not_called()

    def test_remote_tag_movement_is_rejected(self):
        main,tag=rules();env={'GITHUB_REPOSITORY':'example/repo','GITHUB_REF':'refs/heads/main','GITHUB_SHA':'a'*40,'GITHUB_EVENT_NAME':'workflow_dispatch'}
        replies=[{'protected':True,'commit':{'sha':'a'*40}},main,tag,{'object':{'sha':'b'*40}}]
        with mock.patch.dict(os.environ,env),mock.patch.object(PROVENANCE,'api',side_effect=replies),mock.patch.object(PROVENANCE.subprocess,'run',return_value=mock.Mock(returncode=0)):
            with self.assertRaisesRegex(PROVENANCE.PolicyError,'remote tag changed'):
                PROVENANCE.github_policy('v0.2.0','a'*40,{'tag_object':'a'*40},'1','2')


class ArtifactTest(unittest.TestCase):
    def fixture(self, root, git):
        files={}
        for name,path in ARTIFACT.RESOURCES.items():
            content=f'resource {name}'.encode();source=root/path;source.parent.mkdir(parents=True,exist_ok=True);source.write_bytes(content)
            files[ARTIFACT.PREFIX+'Resources/'+name]=content
        # A marker-bearing source file must never execute during validation.
        (root/'Package.swift').write_text('this is not a runnable build manifest')
        git('add','.');git('commit','-m','source');revision=git('rev-parse','HEAD')
        info={'CFBundleExecutable':'Telynd','CFBundleIdentifier':'com.samueladebayo.telynd','CFBundleName':'Telynd','CFBundleDisplayName':'Telynd','CFBundlePackageType':'APPL','CFBundleIconFile':'Telynd','CFBundleShortVersionString':'0.2.0','CFBundleVersion':'2','LSMinimumSystemVersion':'13.0','NSHighResolutionCapable':True,'NSHumanReadableCopyright':'Synthetic fixture','NSAppleEventsUsageDescription':'When you choose a computer, Telynd opens Chrome Remote Desktop and reads that setup tab’s address for up to five minutes. Use open computer reads the front tab once. You confirm before saving.'}
        files[ARTIFACT.PREFIX+'Info.plist']=plistlib.dumps(info)
        files[ARTIFACT.PREFIX+'MacOS/Telynd']=struct.pack('<IIII',0xFEEDFACF,0x0100000C,0,2)+b'synthetic header, never executed'
        files[ARTIFACT.PREFIX+'_CodeSignature/CodeResources']=b'synthetic signature metadata'
        return files,revision

    def archive(self, root, files, extra=None):
        path=root/'input.zip'
        with zipfile.ZipFile(path,'w') as archive:
            for name,data in files.items(): archive.writestr(name,data)
            if extra: archive.writestr(*extra)
        return path

    def test_valid_archive_is_read_as_data_and_resources_match_source(self):
        with repository() as (root,git):
            files,revision=self.fixture(root,git);archive=self.archive(root,files)
            app=ARTIFACT.validate_and_extract(archive,root/'validated','v0.2.0',revision)
            self.assertEqual((app/'Contents/MacOS/Telynd').stat().st_mode & 0o777,0o755)
            self.assertFalse((root/'executed').exists())

    def test_traversal_symlink_extra_files_and_duplicate_are_rejected(self):
        for kind in ['traversal','symlink','extra','duplicate']:
            with self.subTest(kind=kind),repository() as (root,git):
                files,revision=self.fixture(root,git)
                if kind=='traversal': extra=('../escaped',b'bad')
                elif kind=='extra': extra=('Telynd.app/Contents/MacOS/extra',b'bad')
                elif kind=='duplicate': extra=(ARTIFACT.PREFIX+'Info.plist',b'bad')
                else:
                    link=zipfile.ZipInfo(ARTIFACT.PREFIX+'MacOS/Telynd');link.create_system=3;link.external_attr=(stat.S_IFLNK|0o777)<<16
                    files.pop(ARTIFACT.PREFIX+'MacOS/Telynd');extra=(link,b'/tmp/escape')
                archive=self.archive(root,files,extra)
                with self.assertRaises(ValueError): ARTIFACT.validate_and_extract(archive,root/'validated','v0.2.0',revision)
                self.assertFalse((root/'validated').exists());self.assertFalse((root.parent/'escaped').exists())

    def test_tampered_script_wrong_version_and_fixture_metadata_are_rejected(self):
        for kind in ['script','setup_page','linux_helper','version','fixture','automation_missing','automation_changed']:
            with self.subTest(kind=kind),repository() as (root,git):
                files,revision=self.fixture(root,git)
                if kind=='script': files[ARTIFACT.PREFIX+'Resources/setup-remote.sh']=b'tampered'
                elif kind=='setup_page': files[ARTIFACT.PREFIX+'Resources/chrome-setup.html']=b'<script>tampered</script>'
                elif kind=='linux_helper': files[ARTIFACT.PREFIX+'Resources/telynd-setup_0.2.2_all.deb']=b'tampered'
                else:
                    info=plistlib.loads(files[ARTIFACT.PREFIX+'Info.plist'])
                    if kind=='version': info['CFBundleShortVersionString']='9.9.9'
                    elif kind=='fixture': info['TelyndFixtureDirectory']='/tmp/preview'
                    elif kind=='automation_missing': info.pop('NSAppleEventsUsageDescription')
                    else: info['NSAppleEventsUsageDescription']='Unreviewed permission request'
                    files[ARTIFACT.PREFIX+'Info.plist']=plistlib.dumps(info)
                archive=self.archive(root,files)
                with self.assertRaises(ValueError): ARTIFACT.validate_and_extract(archive,root/'validated','v0.2.0',revision)

    def test_oversized_archive_and_existing_destination_are_rejected(self):
        with repository() as (root,git):
            files,revision=self.fixture(root,git);archive=self.archive(root,files)
            with mock.patch.object(ARTIFACT,'LIMIT',10),self.assertRaises(ValueError):
                ARTIFACT.validate_and_extract(archive,root/'validated','v0.2.0',revision)
            (root/'validated').mkdir()
            with self.assertRaises(ValueError): ARTIFACT.validate_and_extract(archive,root/'validated','v0.2.0',revision)

if __name__=='__main__': unittest.main()
