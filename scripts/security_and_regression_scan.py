import os
import re
import sys
import subprocess
import xml.etree.ElementTree as ET

# Text colors for terminal output
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def run_command(command, description):
    print(f"{Colors.OKBLUE}[*] {description}...{Colors.ENDC}")
    try:
        result = subprocess.run(command, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        print(f"{Colors.OKGREEN}[+] Başarılı: {description}{Colors.ENDC}")
        return True, result.stdout
    except subprocess.CalledProcessError as e:
        print(f"{Colors.FAIL}[-] Hata: {description} başarısız oldu!{Colors.ENDC}")
        print(f"{Colors.FAIL}Hata Çıktısı:\n{e.stdout}\n{e.stderr}{Colors.ENDC}")
        return False, e.stdout + e.stderr

def scan_manifest():
    print(f"\n{Colors.HEADER}=== AndroidManifest.xml Güvenlik Analizi ==={Colors.ENDC}")
    manifest_path = "android/app/src/main/AndroidManifest.xml"
    if not os.path.exists(manifest_path):
        print(f"{Colors.WARNING}[!] AndroidManifest.xml bulunamadı. Atlama yapılıyor.{Colors.ENDC}")
        return True

    try:
        tree = ET.parse(manifest_path)
        root = tree.getroot()
        
        # XML Namespaces
        ns = {'android': 'http://schemas.android.com/apk/res/android'}
        
        # Check Application tag
        application = root.find('application')
        issues_found = []
        
        if application is not None:
            # Check allowBackup
            allow_backup = application.attrib.get('{http://schemas.android.com/apk/res/android}allowBackup')
            if allow_backup != 'false':
                issues_found.append("[GİZLİLİK] android:allowBackup değeri 'false' olmalıdır. (Mevcut: {}). Cihaz yedeklemelerinden veri sızabilir.".format(allow_backup))
            
            # Check usesCleartextTraffic
            cleartext = application.attrib.get('{http://schemas.android.com/apk/res/android}usesCleartextTraffic')
            if cleartext == 'true':
                issues_found.append("[GÜVENLİK] android:usesCleartextTraffic='true' olarak ayarlanmış. Güvensiz HTTP trafiğine izin veriliyor.")

        # Check for exported components without permissions
        for activity in root.findall('.//activity'):
            exported = activity.attrib.get('{http://schemas.android.com/apk/res/android}exported')
            name = activity.attrib.get('{http://schemas.android.com/apk/res/android}name')
            if exported == 'true':
                # Check if it's the main launcher activity
                is_launcher = False
                intent_filters = activity.findall('intent-filter')
                for ifilter in intent_filters:
                    actions = ifilter.findall('action')
                    categories = ifilter.findall('category')
                    has_main = any(a.attrib.get('{http://schemas.android.com/apk/res/android}name') == 'android.intent.action.MAIN' for a in actions)
                    has_launcher = any(c.attrib.get('{http://schemas.android.com/apk/res/android}name') == 'android.intent.category.LAUNCHER' for c in categories)
                    if has_main and has_launcher:
                        is_launcher = True
                        break
                
                if is_launcher:
                    continue
                    
                # Check if it has an intent filter but no custom permission
                intent_filter = activity.find('intent-filter')
                permission = activity.attrib.get('{http://schemas.android.com/apk/res/android}permission')
                if intent_filter is not None and not permission:
                    issues_found.append("[GÜVENLİK] Activity '{}' dışa aktarılmış (exported=true) ancak herhangi bir izinle korunmuyor.".format(name))

        if issues_found:
            for issue in issues_found:
                print(f"{Colors.FAIL}[-] Zafiyet: {issue}{Colors.ENDC}")
            return False
        else:
            print(f"{Colors.OKGREEN}[+] AndroidManifest.xml güvenli görünüyor.{Colors.ENDC}")
            return True
    except Exception as e:
        print(f"{Colors.FAIL}[-] Manifest analizinde hata oluştu: {str(e)}{Colors.ENDC}")
        return False

def scan_codebase():
    print(f"\n{Colors.HEADER}=== Kaynak Kod Statik Güvenlik Analizi (SAST) ==={Colors.ENDC}")
    
    # Regex rules
    rules = [
        {
            "name": "Hardcoded Secret / API Key",
            "regex": r"(?i)(api_key|secret|password|private_key|token|auth_token|client_secret)\s*=\s*['\"][a-zA-Z0-9_\-\+\/]{8,}['\"]",
            "type": "GÜVENLİK",
            "description": "Kaynak kodda statik API anahtarı veya şifre tespit edildi."
        },
        {
            "name": "Insecure HTTP Protocol",
            "regex": r"['\"]http://[a-zA-Z0-9\.\/\-\?\#\=\&\%\_]+['\"]",
            "type": "GÜVENLİK",
            "description": "Güvensiz HTTP bağlantısı tespit edildi. HTTPS kullanılmalıdır."
        },
        {
            "name": "Weak Cryptography (MD5/SHA-1)",
            "regex": r"(?i)(md5|sha1)\b",
            "type": "GÜVENLİK",
            "description": "Zayıf şifreleme algoritması (MD5/SHA-1) kullanımı tespit edildi."
        }
    ]

    clean = True
    for root_dir, dirs, files in os.walk("."):
        # Exclude build, ios, android, .dart_tool, .git
        if any(x in root_dir for x in ["build", "ios", ".dart_tool", ".git", "android/app/build"]):
            continue
            
        for file in files:
            if not file.endswith(('.dart', '.java', '.kt')):
                continue
                
            file_path = os.path.join(root_dir, file)
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    
                for rule in rules:
                    matches = re.finditer(rule["regex"], content)
                    for match in matches:
                        # Simple false positive checks
                        matched_text = match.group(0)
                        if "api.testsprite.com" in matched_text or "placeholder" in matched_text.lower() or "example" in matched_text.lower():
                            continue
                        
                        # Find line number
                        line_no = content.count('\n', 0, match.start()) + 1
                        print(f"{Colors.FAIL}[-] {rule['type']} - {rule['name']} ({file_path}:{line_no}){Colors.ENDC}")
                        print(f"    Tespit: {matched_text.strip()}")
                        print(f"    Açıklama: {rule['description']}")
                        clean = False
            except Exception as e:
                pass
                
    if clean:
        print(f"{Colors.OKGREEN}[+] Kaynak kodda güvenlik veya gizlilik ihlali bulunamadı.{Colors.ENDC}")
    return clean

def main():
    print(f"{Colors.BOLD}{Colors.HEADER}=================================================={Colors.ENDC}")
    print(f"{Colors.BOLD}{Colors.HEADER}       OTONOM STATİK GÜVENLİK VE REGRESYON TESTİ   {Colors.ENDC}")
    print(f"{Colors.BOLD}{Colors.HEADER}=================================================={Colors.ENDC}")
    
    # 1. Kod Analizi (Flutter Analyze)
    analyze_ok, _ = run_command("flutter analyze", "Flutter Kod Kalitesi ve Hata Analizi")
    if not analyze_ok:
        sys.exit(1)
        
    # 2. Birim ve Entegrasyon Testleri (Flutter Test)
    test_ok, _ = run_command("flutter test", "Flutter Otomatik Test Senaryoları")
    if not test_ok:
        sys.exit(1)
        
    # 3. AndroidManifest Analizi
    manifest_ok = scan_manifest()
    
    # 4. Kaynak Kod Zafiyet Analizi (SAST)
    sast_ok = scan_codebase()
    
    if not manifest_ok or not sast_ok:
        print(f"\n{Colors.FAIL}[-] Güvenlik ve Gizlilik Taraması Hata/Zafiyet Bildirdi!{Colors.ENDC}")
        sys.exit(1)
        
    print(f"\n{Colors.OKGREEN}[+] TEBRİKLER! Tüm testler, kalite analizleri ve güvenlik taramaları sıfır hata ile tamamlandı!{Colors.ENDC}")
    sys.exit(0)

if __name__ == "__main__":
    main()
