import hashlib,json,zlib,struct,zipfile
from pathlib import Path
import zstandard as zs
def sha(b):return hashlib.sha256(b).hexdigest()
files,modes=json.loads(zlib.decompress(Path('layout.z').read_bytes()))
payload=b''.join(p.read_bytes() for p in sorted(Path('.').glob('part-*')))
def take(pair):return payload[pair[0]:sum(pair)]
base=zipfile.ZipFile('base.zip')
for os,spec in modes.items():
 prefix='Servobsh/'
 manifest={}
 with zipfile.ZipFile(f'Servobsh-R5-{os}.zip','w',zipfile.ZIP_DEFLATED) as archive:
  for name,(key,attr) in spec.items():
   diff=files[key]
   try:old=base.read('Servobsh/'+name)
   except KeyError:old=b''
   if diff is None:data=old
   elif isinstance(diff,list):data=take(diff)
   else:
    head=bytearray(4096);body=bytearray()
    for i,*patch in diff['records']:
     p=(int.from_bytes(old[i*4:i*4+4],'big')>>8)*4096 if old else 0
     blob=old[p+5:p+4+int.from_bytes(old[p:p+4],'big')] if p else b''
     if patch:
      orig=zlib.decompress(blob) if blob else b''
      codec=zs.ZstdDecompressor(dict_data=zs.ZstdCompressionDict(orig,dict_type=zs.DICT_TYPE_RAWCONTENT) if orig else None)
      raw=codec.decompress(take(patch[0]));assert sha(raw)==patch[1]
      blob=zlib.compress(raw)
     record=struct.pack('>IB',len(blob)+1,2)+blob
     n=(len(record)+4095)//4096;struct.pack_into('>I',head,i*4,((len(body)//4096+2)<<8)|n)
     body.extend(record);body.extend(bytes(4096*n-len(record)))
    data=head+take(diff['stamps'])+body
   original=data
   if name in ("play.command","play.ps1"):data=Path("update",name).read_bytes()
   if name in ("ПРОЧТИ-МЕНЯ.txt","START-WINDOWS.txt"):data=Path("update/guide.txt").read_bytes()
   manifest[name]=sha(data)
   if not isinstance(diff,dict):assert sha(original)==key,name
   info=zipfile.ZipInfo(prefix+name);info.external_attr=attr;info.create_system=3;archive.writestr(info,data,zipfile.ZIP_DEFLATED)
  archive.writestr(prefix+'MANIFEST.sha256.json',json.dumps(manifest,indent=2))
 with zipfile.ZipFile(f'Servobsh-R5-{os}.zip') as z:
  assert all(sha(z.read(prefix+n))==h for n,h in manifest.items())
