;;; init.el --- Native Emacs IDE entry point -*- lexical-binding: t; -*-

;; Package installation is explicit: M-x lcw-install-ide-packages.
;; Ordinary startup never refreshes archives or downloads packages.
(require 'package)
(setq package-archives '(("gnu" . "https://elpa.gnu.org/packages/")
                         ("nongnu" . "https://elpa.nongnu.org/nongnu/")
                         ("melpa" . "https://melpa.org/packages/")))
(package-initialize)
(require 'use-package)
(setq use-package-always-ensure nil)

;; dired-subtree contains guarded compatibility calls to optional Dired
;; extensions that confuse the native compiler on Emacs 30. Keep this small,
;; older package on byte-code so harmless diagnostics do not open *Warnings*.
(defvar native-comp-jit-compilation-deny-list nil)
(add-to-list 'native-comp-jit-compilation-deny-list
             "/dired-subtree-[^/]+/dired-subtree\\.el\\'")

;; Local configuration modules and pinned code not distributed through ELPA.
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(add-to-list 'load-path
             (expand-file-name "vendor/markdown-mode" user-emacs-directory))

(defconst lcw-ide-packages
  '(vertico orderless marginalia consult corfu magit dired-subtree vterm dape lua-mode pdf-tools
    autothemer avy embark embark-consult yasnippet cape multiple-cursors
    paredit vlf)
  "Packages installed explicitly by `lcw-install-ide-packages'.")

(defconst lcw-theme-packages
  '(doom-themes catppuccin-theme nord-theme gruvbox-theme solarized-theme
    nerd-icons nerd-icons-dired nerd-icons-corfu nerd-icons-completion)
  "Theme and icon packages installed by `lcw-install-ide-packages'.")

(defun lcw-install-ide-packages ()
  "Install missing IDE and theme packages from configured archives."
  (interactive)
  (package-refresh-contents)
  (dolist (pkg (append lcw-ide-packages lcw-theme-packages))
    (unless (package-installed-p pkg)
      (package-install pkg)))
  (message "Packages installed. Restart Emacs to enable all settings."))

;; Keep Customize output separate from the version-controlled configuration.
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(load custom-file 'noerror 'nomessage)
(setq package-selected-packages (append lcw-ide-packages lcw-theme-packages))

;; Dedicated language tools, including Node for desktop-launched Emacs.
(dolist (tool-dir
         (list "/home/lcw/.local/share/pi-node/node-v22.23.2-linux-x64/bin"
               (expand-file-name "tools/node/node_modules/.bin"
                                 user-emacs-directory)
               (expand-file-name "tools/python/bin" user-emacs-directory)
               (expand-file-name "tools/lua-ls/bin" user-emacs-directory)))
  (when (file-directory-p tool-dir)
    (add-to-list 'exec-path tool-dir)
    (setenv "PATH" (concat tool-dir path-separator (getenv "PATH")))))

;; Each package has one owning module. The order makes shared facilities such
;; as completion and projects available before programming integrations load.
(dolist (module '(init-minibuffer
                  init-editing
                  init-ui
                  init-project
                  init-programming))
  (require module))

;;; init.el ends here
