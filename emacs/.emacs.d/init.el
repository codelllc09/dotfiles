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

;; Let terminal tools reuse this Emacs instance through `emacsclient'.
(require 'server)
(defconst lcw-external-editor-command "emacsclient -t -a \"\""
  "Editor command exported to terminal tools started by Emacs.")
(setenv "VISUAL" lcw-external-editor-command)
(setenv "EDITOR" lcw-external-editor-command)

(defun lcw-start-emacs-server ()
  "Start the default Emacs server once."
  (unless (or noninteractive (server-running-p))
    (server-start)))
(add-hook 'emacs-startup-hook #'lcw-start-emacs-server)
(when after-init-time
  (lcw-start-emacs-server))

(defvar native-comp-jit-compilation-deny-list nil)
;; dired-subtree native-comp exclusion retired with the package (2026-10):
;; it kept that small package on byte-code because its guarded calls to
;; optional Dired extensions confused the native compiler on Emacs 30.
;; (add-to-list 'native-comp-jit-compilation-deny-list
;;              "/dired-subtree-[^/]+/dired-subtree\\.el\\'")
;; Agent Shell optionally calls Emacs 31's system-sleep API behind `fboundp'.
;; Emacs 30 handles that correctly at runtime but its native compiler reports
;; the guarded calls as undefined.  Keep only the main file on byte-code until
;; that API exists; the smaller Agent Shell modules can still compile natively.
(when (< emacs-major-version 31)
  (add-to-list 'native-comp-jit-compilation-deny-list
               "/agent-shell\\(?:-[^/]+\\)?/agent-shell\\.el\\'"))

;; The async native compiler re-reports unresolved cross-package references
;; (Dirvish side panel, consult, doom-themes glue, ...) whenever the eln cache
;; is rebuilt.  Every one of them is a known load-order coupling, so keep the
;; reports out of *Warnings*; they are still recorded in
;; *Async Native Compile Log*.
(defvar native-comp-async-report-warnings-errors) ; defined in C (comp.c)
(setq native-comp-async-report-warnings-errors 'silent)
;; Local configuration modules and pinned code not distributed through ELPA.
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(add-to-list 'load-path
             (expand-file-name "lisp"
                               (file-name-directory
                                (file-truename
                                 (or load-file-name user-init-file)))))
(add-to-list 'load-path
             (expand-file-name "vendor/markdown-mode" user-emacs-directory))

(defconst lcw-ide-packages
  '(vertico orderless marginalia consult corfu magit dirvish
    ;; dired-subtree  ; retired 2026-10: Dirvish ships its own subtree
    vterm dape lua-mode pdf-tools
    autothemer avy embark embark-consult yasnippet cape multiple-cursors
    paredit vlf agent-shell flymake-ruff diff-hl hl-todo)
  "Packages installed explicitly by `lcw-install-ide-packages'.")

(defconst lcw-theme-packages
  '(doom-themes doom-modeline catppuccin-theme nord-theme gruvbox-theme
    solarized-theme nerd-icons nerd-icons-dired nerd-icons-corfu
    nerd-icons-completion dashboard page-break-lines)
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
(setq package-selected-packages
      (append lcw-ide-packages lcw-theme-packages '(agent-shell-tramp)))

;; Dedicated language tools, including Node for desktop-launched Emacs.
(dolist (tool-dir
         (list (expand-file-name "~/.local/share/pi-node/current/bin")
               (expand-file-name "tools/node/node_modules/.bin"
                                 user-emacs-directory)
               (expand-file-name "tools/python/bin" user-emacs-directory)
               (expand-file-name "tools/lua-ls/bin" user-emacs-directory)))
  (when (file-directory-p tool-dir)
    (add-to-list 'exec-path tool-dir)
    (setenv "PATH" (concat tool-dir path-separator (getenv "PATH")))))

;; Each package has one owning module. The order makes shared facilities such
;; as completion and projects available before programming integrations load;
;; init-docs/init-dashboard/init-terminal sit after the modules whose
;; commands and faces they consume (see each file's header).
(dolist (module '(init-minibuffer
                  init-editing
                  init-docs
                  init-ui
                  init-project
                  init-dashboard
                  init-terminal
                  init-agent
                  init-programming
                  init-doctor))
  (require module))

;;; init.el ends here
