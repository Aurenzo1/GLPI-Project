import subprocess, sys
VBM = r"C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
# Pour obtenir le caractère X sur un invité en AZERTY, quelle touche US envoyer
M = {'a':'q','q':'a','z':'w','w':'z','m':';','A':'Q','Q':'A','Z':'W','W':'Z','M':':',
     '1':'!','2':'@','3':'#','4':'$','5':'%','6':'^','7':'&','8':'*','9':'(','0':')',
     '-':'6','_':'8','=':'=','+':'+',')':'-','(':'5','&':'1','"':'3',"'":'4',
     ',':'m',';':',',':':'.','!':'/','.':'<','/':'>','*':chr(92),'$':']','?':'M'}
def tr(s):
    out=[]
    for ch in s:
        if ch in M: out.append(M[ch])
        elif ch.isalpha() or ch in ' \n': out.append(ch)
        else: raise SystemExit(f"caractere non traduisible: {ch!r}")
    return ''.join(out)
vm, cmd = sys.argv[1], sys.argv[2] + "\n"
subprocess.run([VBM,"controlvm",vm,"keyboardputstring",tr(cmd)], check=True)
print("injecté :", cmd.strip())
