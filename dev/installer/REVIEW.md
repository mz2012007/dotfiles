# تقييم `install.sh` القديم ونتيجة إعادة البناء

## 1. الملخص التنفيذي

السكربت القديم في `mz2012007/dotfiles` يقوم بالمهمة، لكنه غير آمن كأداة
تثبيت عامة: يفتح ثغرات صلاحيات، يغيّر ملكية ملفات نظام، يعيد كتابة ملفات
إعداد كاملة، ويعتمد على `fzf` وتفاعل يدوي في كل خطوة. كما أنه غير
idempotent، ولا يملك dry-run أو حالة قابلة للاستئناف.

تم بناء بديل باسم **`voidsetup`** في `dev/installer/`:

- Python 3.11+ و`asyncio` لكل مهمة.
- واجهة Textual كاملة + CLI غير تفاعلي.
- 28 مهمة قابلة للاختيار، 6 profiles، وفحص preflight/doctor.
- اختيار حزم فردية يدوياً في الـTUI (بالإضافة للمجموعات)، و`--packages` في الـCLI.
- منتقي ألوان للـTUI نفسه (Ctrl+T) مع حفظ الاختيار في الإعدادات.
- حالة JSON ذرّية، سجلات، resume، dry-run، واختبارات آلية.
- لا SUID، ولا إضافة إلى `root`، ولا `chown -R` لملفات النظام.

## 2. تقييم السكربت القديم

### نقاط قوة حقيقية

- يغطي احتياجات الجهاز الفعلية: repos، timezone، packages، dotfiles،
  services، بناء dwm/dwmblocks، TPM، mpv، الخطوط، Plymouth وGRUB.
- يستخدم `packages.sh` كمصدر واحد لمجموعات الحزم.
- يحتوي على أفكار جيدة مثل `set -euo pipefail` ووجود profiles.
- ينبّه عند غياب بعض الملفات المصدرية.

### مشاكل أمنية حرجة

| المشكلة في السكربت القديم | لماذا هي خطيرة | الحل في `voidsetup` |
| --- | --- | --- |
| `chmod u+s /usr/bin/sleep` و`/usr/sbin/sleep` | أي مستخدم يستطيع تشغيل `sleep` بصلاحيات root؛ وهذا يفتح باب privilege escalation | حُذف نهائياً |
| SUID على `poweroff` و`reboot` و`hostname` و`zzz` | توسيع سطح الهجوم بدل استخدام polkit/sudoers | مهمة `power_polkit` تكتب قاعدة polkit ضيقة لـ `power-off`/`reboot`/`suspend` فقط، ومهمة `harden_suid` تزيل البتات القديمة |
| إضافة المستخدم إلى `root` و`sys` و`kmem` و`tty` و`xbuilder`... | صلاحيات نظام واسعة جداً | قائمة مجموعات منقّحة، مع رفض صريح للمجموعات الحساسة |
| `chown -R "$USER:$USER" "$HOME"` | يغيّر ملكية كل شيء في المنزل، بما في ذلك ما ليس ملكاً للسكربت | لم تُنقل |
| `chown -R "$USER:$USER" /var/log` | يكسر ملكية سجلات النظام | حُذف؛ `doctor` يكتشف الضرر القديم |
| `chown -R "$USER:$USER" /var/run/docker.sock` | حل خاطئ لمشكلة المجموعة | يُستخدم group `docker` بدلاً منه |
| `ARR=(...)` مع `source` قبل `set -euo pipefail` | تنفيذ ملف غير موثوق قبل تفعيل الحماية | تحليل `packages.sh` نصياً دون تنفيذه |
| `sudo sh -c "echo ... > /etc/xbps.d/..."` | بناء أوامر بـ shell؛ خطر حقن | كتابة ذرّية عبر `tee` وchmod/chown محددين |

### مشاكل منطقية وتشغيلية

| المشكلة | التفصيل | الحل |
| --- | --- | --- |
| `error()` لا تُنهي السكربت | تطبع رسالة فقط، و`\|\| error` يعيد 0، لذلك يستمر التثبيت بعد الفشل | استثناءات `TaskFailed` وعوائق dependencies وseverity لكل مهمة |
| `source packages.sh` مرتين | مرة قبل `set -e` ومرة داخل `CHECK` | تحميل واحد عبر `PackageCatalog` |
| `stow .` فقط | ليس idempotent؛ يفشل عند وجود ملفات غير مُدارة | `stow --restow` مع `--simulate` وفحص تعارضات |
| `sudo rm -r $tpm_dir` بدون quotes | خطر حذف مسار خاطئ، ويعيد استنساخ TPM كل مرة | تحديث `git pull` بدلاً من الحذف، ومسارات مقتبسة |
| `"$HOME/.config/tmux/templates/ "` | مسافة زائدة تصنع مجلداً باسم غريب | مهمة `cleanup_stray` تحذف المجلد القديم، والمسار الصحيح في الإعدادات |
| `chattr +i /etc/resolv.conf` دائماً | يمنع NetworkManager/DHCP من تحديث DNS، و`cp -a` يجعل الملف مملوكاً للمستخدم | الكتابة root-owned، ورفع immutable افتراضياً، وخيار `resolv_immutable` |
| `sudo tee /etc/sysctl.conf` | يمحو أي إعدادات قديمة في الملف | الكتابة إلى `/etc/sysctl.d/99-voidsetup.conf` |
| `sudo mkdir -p /var/run/docker.sock` | المسار socket وليس directory؛ قد يوقف السكربت | حُذف من قائمة المجلدات |
| `MY_PKGS` يثبّت `ccze` فقط | يتجاهل بقية ملفات `.xbps` | فهرسة كل الملفات واستخراج الأسماء وتثبيت الناقص فقط |
| `GROUPS` بدون فحص وجود | يطبع نجاحاً حتى عند فشل `usermod` | فحص المجموعات الموجودة والحالية، وإضافة الناقص فقط |
| `old_lab` يتضمن `MV_HOME` | ينقل محتويات المنزل فعلياً ضمن المسار الافتراضي | `backup_home` مهمة خطرة منفصلة في profile `fresh` فقط |
| `RSYNC` يستخدم `sudo` لكل شيء | ملكية غير متوقعة لملفات المستخدم، ونسخ root configs بملكية المستخدم | `root_owned` لكل زوج، و`--chown=root:root` عند اللزوم |
| `SERVICES` تضم `dhcpcd` مع NetworkManager | تعارض محتمل في إدارة الشبكة | أزيلت من الافتراضي |
| `FINISH` و`PLYMOUTH` تفاعليان | لا يصلحان للتشغيل غير التفاعلي | `--plymouth-theme` و`--reboot`، وTUI منفصل |
| لا dry-run / state / resume | أي خطأ يترك الجهاز في منتصف التثبيت | dry-run، حالة JSON، `--resume`، `--fresh` |
| `CHECK` لا يفحص الأوامر فعلياً | الحلقة تحتوي `true` فقط | preflight يبني متطلبات كل مهمة ويفحصها |
| `SUDO_PRIV` حلقة خلفية غير مُدارة | قد تبقى أو تُقتل بطريقة خاطئة | keepalive داخل `asyncio` ويُوقف عند النهاية |
| `CLEANUP` على EXIT فقط | لا يتعامل مع SIGINT/SIGTERM بشكل منظم | إشارات CLI تُطلب إيقافاً آمناً بعد الأمر الحالي |

### تقييم عام (من 10)

| المحور | السكربت القديم | `voidsetup` |
| --- | --- | --- |
| الأمان | 3 | 8.5 |
| الموثوقية / idempotency | 3 | 8.5 |
| قابلية الاستئناف والمراقبة | 1 | 9 |
| قابلية الصيانة والاختبار | 3 | 8.5 |
| تجربة المستخدم | 6 (fzf) | 9 (TUI + CLI) |
| الاكتمال الوظيفي | 8 | 8.5 |

## 3. ما تم بناؤه

```
dev/installer/
├── pyproject.toml
├── README.md
├── REVIEW.md
├── src/voidsetup/
│   ├── cli.py            # run/plan/list/profiles/packages/doctor/themes/schemes/init-config/tui
│   ├── app.py            # Textual App + CSS
│   ├── models.py         # Task, Profile, TaskResult, RunOptions, Enums
│   ├── registry.py       # 28 مهمة + 6 profiles + dependency resolution
│   ├── engine.py         # تنفيذ متسلسل، resume، check، severity، dangerous
│   ├── runner.py         # subprocess غير متزامن + dry-run + timeout + cancel
│   ├── context.py        # واجهة المهام: run/probe/write_file/mkdir/symlink/remove
│   ├── state.py          # JSON ذرّي + quarantine
│   ├── session_log.py    # سجل موحد للـ CLI والـTUI
│   ├── preflight.py      # فحص البيئة + تدقيق أضرار السكربت القديم
│   ├── packages.py       # تحليل packages.sh + aliases + missing
│   ├── config.py         # TOML + env + default paths
│   ├── sudo.py           # sudo -n / ensure_sudo
│   ├── screens/          # Welcome, Profile, Plan, Packages, Theme, Execution, Summary, Doctor, Confirm
│   └── tasks/            # system, packages, dotfiles, services, build, security, finish
└── tests/                # 150 اختباراً
```

### الميزات الأساسية

- **Task model**: `id`, `name`, `description`, `group`, `requires_root`,
  `severity`, `depends_on`, `dangerous`, `check`, `rollback` (محجوز).
- **Execution engine**: يوقف الخطة عند فشل مهمة required، ويستمر بعد فشل
  optional، ويحجب dependents عند فشل dependency.
- **Idempotency**: `check()` لكل مهمة تقريباً (repos، timezone، stow،
  packages، services، groups، sysctl، dns، ufw، plymouth، ...).
- **Dry-run**: لا ينفذ أوامر تغيير، لكنه يشغّل probes للقراءة فقط.
- **State**: `~/.local/state/voidsetup/state.json`، كتابة ذرّية، واستئناف
  دون إعادة تنفيذ المهام المكتملة، مع رفض الاستئناف إذا تغيّرت الخطة
  (`--fresh` للبدء من جديد).
- **Logs**: `~/.local/state/voidsetup/logs/YYYYMMDD-HHMMSS.log` مع pruning.
- **Sudo**: `sudo -n` لكل أمر، مع keepalive كل 45 ثانية، و`ensure_sudo`
  تفاعلي في الواجهة.
- **CLI JSON**: `--json` مع `--yes`، وكل الرسائل البشرية إلى stderr.
- **TUI**: شاشات مترابطة، جدول حالة، شريط تقدم، سجل حي، إيقاف آمن، ملخص،
  واستئناف المهام الفاشلة، وإعادة تشغيل فقط عند نجاح المطلوب.
- **Repair profile**: `harden_suid` + `dns` + `cleanup_stray` لإصلاح
  الأضرار المعروفة للسكربت القديم دون لمس بقية النظام.

## 4. خريطة الترحيل من Bash إلى Python

| الدالة القديمة | المهمة الجديدة |
| --- | --- |
| `WELCOME`, `FINISH` | `finish` + شاشات TUI |
| `CHECK` | `preflight.py` + `doctor` |
| `REPO` | `repos` |
| `DNS` | `dns` |
| `LOCALTIME` | `timezone` |
| `TIME` | `sync_time` |
| `UPDATE_SYSTEM` | `update` |
| `SELECT_PACKAGES_FZF` | `packages` + شاشة اختيار المجموعات والحزم الفردية |
| `MV_HOME` | `backup_home` (خطرة، `fresh` فقط) |
| `MK_USER_DIRS` | `dirs_user` |
| `MK_ROOT_DIRS` | `dirs_root` |
| `STOW` | `stow` (مع `--restow` وفحص التعارضات) |
| `RSYNC` | `copy_configs` |
| `MK_FILES` | `mk_files` |
| `PRIVILEGES` | `power_polkit` + `harden_suid` + `groups` الآمنة |
| `DWM` | `dwm` + `dwmblocks` |
| `SHELL` | لم تُنقل (تغيير shell قرار شخصي) |
| `SERVICES` | `services` |
| `TMUX` | `tmux` |
| `MPV` | `mpv` |
| `MY_PKGS` | `local_packages` |
| `FONTS` | `fonts` |
| `GROUPS` | `groups` |
| `CACHE` | `sysctl` |
| `PRIVACY` | `ufw` |
| `PLYMOUTH` | `plymouth` |
| `GRUB` | `grub` |
| `FZF_ENSURE` | لم تعد مطلوبة |

## 5. ما اكتشفه `doctor` على هذا الجهاز

هذه نتائج حقيقية من تشغيل `voidsetup doctor`، وليست افتراضات:

1. `/etc/resolv.conf` مملوك للمستخدم `mz` وليس root، وعليه immutable flag
   من السكربت القديم. مهمة `dns` تصلح الملكية وترفع العلم افتراضياً.
2. `/var/log` مملوك للمستخدم `mz` — أثر `chown -R` القديم.
3. يوجد مجلد `~/.config/tmux/templates/ ` بمسافة زائدة؛ مهمة
   `cleanup_stray` تحذفه.
4. يوجد تعارضا stow فعليان:
   `~/.config/mimeapps.list` و`~/.config/pavucontrol.ini` ليسا symlinks.
   `stow` سيتوقف ويقترح النقل إلى backup، أو يمكن استخدام
   `--allow-destructive` للنسخ الاحتياطي التلقائي.
5. مصدران في `RSYNC` غير موجودين في الـcheckout الحالي:
   `my-safe.rules` و`.ssh/agent/`؛ المهمة تتخطاهما مع تحذير.
6. `/etc/localtime` مضبوط بالفعل على `Africa/Cairo`.
7. `pkg-xbps/` يحتوي `ccze-2.19_1.x86_64.xbps` و`x86_64-repodata` وملف
   `xmonad` غير حزمة؛ مهمة `local_packages` تتعامل مع `.xbps` فقط.

## 6. التحقق الذي تم

- `python -m compileall -q src` ناجح.
- `150` اختبارات pytest ناجحة (وحدات + CLI + TUI في وضع dry-run، وتغطية اختيار الحزم اليدوي ومنتقي الألوان).
- `voidsetup doctor` يعمل ويعرض التحذيرات الحقيقية أعلاه.
- `voidsetup plan --profile during_work` و`run --dry-run --yes` ناجحان.
- `voidsetup run --json --dry-run --yes` يطبع JSON صالحاً فقط على stdout.
- TUI: Welcome → Profile → Plan → Package groups → تنفيذ dry-run → Summary
  تم اختبارها آلياً.
- لم تُنفَّذ أي مهمة مدمّرة أو تغيير نظام حقيقي على هذا الجهاز أثناء
  التطوير؛ كل اختبارات النظام كانت dry-run أو read-only.

## 7. القيود والخطوات القادمة

- **لا rollback تلقائي**: الحالة والـlog يسمحان بالاستئناف، لكن لا يوجد
  تراجع عن تعديل جزئي. الحقل `rollback` موجود في model وجاهز للتنفيذ.
- **التنفيذ متسلسل**: يمكن إضافة مجموعات متوازية للمهام المستقلة
  (`fonts` + إنشاء المجلدات) لاحقاً.
- **تعارضات stow المعقدة**: الحل الحالي يتعامل مع تعارضات الملفات/المجلدات
  المباشرة؛ الحالات الشاذة قد تحتاج تدخلاً يدوياً.
- **لم تُنقل `SHELL`**: تغيير shell المستخدم وroot قرار شخصي وليس جزءاً من
  التثبيت الآمن.
- **التوصية**: شغّل `voidsetup doctor` أولاً، ثم `--dry-run`، ثم ابدأ
  بـ`during_work` قبل `old_lab` أو `fresh`.

## 8. الخلاصة

السكربت القديم كان “يعمل” لكنه يخالف مبادئ أقل الصلاحيات، ولا يصلح
للتشغيل المتكرر. البديل الحالي يحافظ على نفس الوظائف المفيدة، ويضيف
أماناً ووضوحاً وقابلية للاختبار والاستئناف، مع إبقاء كل تغيير نظام صريحاً
وقابلاً للمراجعة قبل التنفيذ.
