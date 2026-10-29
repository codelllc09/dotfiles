;;; init-programming.el --- Languages, diagnostics, formatting, and debugging -*- lexical-binding: t; -*-

(require 'project)
(require 'eglot)
(require 'treesit)

;; flymake-ruff calls the Emacs 30 Flymake accessor
;; `flymake-diagnostic-text' but does not require/declare Flymake in its source,
;; so native compilation reports a false undefined-function warning.  The
;; package ships working byte-code; keep it there until upstream adds the
;; declaration, avoiding a noisy *Warnings* buffer without disabling Ruff.
(when (boundp 'native-comp-jit-compilation-deny-list)
  (add-to-list 'native-comp-jit-compilation-deny-list
               "/flymake-ruff-[^/]+/flymake-ruff\\.el\\'"))

(use-package eglot
  :ensure nil
  :commands (eglot eglot-rename eglot-format-buffer eglot-code-actions)
  :custom
  ;; Start the language server without blocking editing while it initializes.
  (eglot-sync-connect nil)
  :bind (("C-c l l" . eglot)
         ("C-c l r" . eglot-rename)
         ("C-c l f" . eglot-format-buffer)
         ("C-c l a" . eglot-code-actions)))

(use-package flymake
  :ensure nil
  :hook (emacs-lisp-mode . flymake-mode)
  :bind (("C-c ! l" . flymake-show-buffer-diagnostics)
         ("C-c ! p" . flymake-show-project-diagnostics)
         ("C-c ! n" . flymake-goto-next-error)
         ("C-c ! b" . flymake-goto-prev-error)))

(defconst lcw-todo-search-regexp
  "\\b(TODO|FIXME|BUG|HACK|NOTE|REVIEW|DEPRECATED|XXX)\\b"
  "Regular expression used for project-wide code-note searches.")

(defun lcw-search-project-todos ()
  "Search the current project for TODO-style code notes."
  (interactive)
  (let ((root (if-let* ((project (project-current nil)))
                  (project-root project)
                default-directory)))
    (if (fboundp 'consult-ripgrep)
        (consult-ripgrep root lcw-todo-search-regexp)
      (rgrep lcw-todo-search-regexp "*" root))))

(defvar-keymap lcw-todo-prefix-map
  :doc "TODO and code-note commands."
  "n" #'hl-todo-next
  "p" #'hl-todo-previous
  "o" #'hl-todo-occur
  "s" #'lcw-search-project-todos)

(keymap-global-set "C-c n" lcw-todo-prefix-map)

(use-package hl-todo
  :if (locate-library "hl-todo")
  :commands (hl-todo-mode hl-todo-next hl-todo-previous hl-todo-occur)
  :hook (prog-mode . hl-todo-mode)
  :custom
  (hl-todo-highlight-punctuation ":")
  (hl-todo-text-modes nil)
  (hl-todo-keyword-faces
   '(("TODO" warning bold)
     ("FIXME" error bold)
     ("BUG" error bold)
     ("HACK" font-lock-constant-face bold)
     ("NOTE" success bold)
     ("REVIEW" font-lock-keyword-face bold)
     ("DEPRECATED" font-lock-doc-face bold)
     ("XXX" font-lock-constant-face bold))))

(defvar-keymap lcw-fold-prefix-map
  :doc "Code folding commands."
  "z" #'hs-toggle-hiding
  "a" #'hs-hide-all
  "s" #'hs-show-all)

(keymap-global-set "C-c z" lcw-fold-prefix-map)

(use-package hideshow
  :ensure nil
  :hook (prog-mode . hs-minor-mode))

(defun lcw-python-enable-ruff-diagnostics ()
  "Enable live Ruff diagnostics when Ruff exists on the current host."
  ;; With a TRAMP default-directory, REMOTE asks `executable-find' to inspect
  ;; the remote host rather than accidentally using the bundled local Ruff.
  (when (executable-find "ruff" t)
    (flymake-ruff-load)
    (flymake-mode 1)))

(use-package flymake-ruff
  :if (locate-library "flymake-ruff")
  :commands (flymake-ruff-load flymake-ruff-goto-doc)
  :hook (python-base-mode . lcw-python-enable-ruff-diagnostics)
  :config
  (with-eval-after-load 'flymake
    (keymap-set flymake-diagnostics-buffer-mode-map
                "M-RET" #'flymake-ruff-goto-doc)
    (keymap-set flymake-project-diagnostics-mode-map
                "M-RET" #'flymake-ruff-goto-doc)))

(setq treesit-language-source-alist
      '((c "https://github.com/tree-sitter/tree-sitter-c" "v0.23.4")
        (cpp "https://github.com/tree-sitter/tree-sitter-cpp" "v0.23.4")
        (python "https://github.com/tree-sitter/tree-sitter-python" "v0.23.6")
        (javascript "https://github.com/tree-sitter/tree-sitter-javascript" "v0.23.1" "src")
        (typescript "https://github.com/tree-sitter/tree-sitter-typescript" "v0.23.2" "typescript/src")
        (tsx "https://github.com/tree-sitter/tree-sitter-typescript" "v0.23.2" "tsx/src")))

(when (treesit-ready-p 'c t)
  (add-to-list 'major-mode-remap-alist '(c-mode . c-ts-mode)))
(when (and (treesit-ready-p 'c t) (treesit-ready-p 'cpp t))
  (add-to-list 'major-mode-remap-alist '(c++-mode . c++-ts-mode)))
(when (treesit-ready-p 'python t)
  (add-to-list 'major-mode-remap-alist '(python-mode . python-ts-mode)))
(when (treesit-ready-p 'javascript t)
  (add-to-list 'major-mode-remap-alist '(js-mode . js-ts-mode))
  (add-to-list 'major-mode-remap-alist '(javascript-mode . js-ts-mode)))
(when (treesit-ready-p 'typescript t)
  (add-to-list 'auto-mode-alist '("\\.ts\\'" . typescript-ts-mode)))
(when (treesit-ready-p 'tsx t)
  (add-to-list 'auto-mode-alist '("\\.[jt]sx\\'" . tsx-ts-mode)))

(use-package lua-mode
  :if (locate-library "lua-mode")
  :mode "\\.lua\\'")

(defun lcw-project-root ()
  "Return the project root, or the current directory."
  (if-let* ((project (project-current nil)))
      (project-root project)
    default-directory))

(defvar-local lcw-python-interpreter nil
  "Optional Python executable override.")

(defun lcw-python-executable ()
  "Choose explicit Python, project .venv, or a suitable default."
  (or lcw-python-interpreter
      (let ((venv (expand-file-name ".venv/bin/python" (lcw-project-root))))
        (when (file-executable-p venv) (file-local-name venv)))
      (if (file-remote-p default-directory)
          "python3"
        (expand-file-name "tools/python/bin/python" user-emacs-directory))))

(defun lcw-python-setup ()
  "Use the project interpreter for the REPL and Pyright import resolution."
  (setq-local python-shell-interpreter (lcw-python-executable))
  (setq-local eglot-workspace-configuration
              `(:python (:pythonPath ,python-shell-interpreter))))

(defun lcw-org-babel-python-setup ()
  "Use the project Python interpreter for Org Babel blocks."
  (setq-local org-babel-python-command (lcw-python-executable)))

(use-package org
  :ensure nil
  :hook (org-mode . lcw-org-babel-python-setup)
  :config
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (python . t))))

(defun lcw-select-python (interpreter)
  "Select INTERPRETER for this buffer; reconnect Eglot afterwards."
  (interactive "fPython executable: ")
  (setq-local lcw-python-interpreter (file-local-name interpreter))
  (lcw-python-setup)
  (message "Python: %s. M-x eglot-reconnect refreshes the running server."
           python-shell-interpreter))

(add-to-list 'eglot-server-programs
             '((python-mode python-ts-mode) . ("pyright-langserver" "--stdio")))
(add-to-list 'eglot-server-programs
             '(((js-mode :language-id "javascript")
                (js-ts-mode :language-id "javascript")
                (typescript-ts-mode :language-id "typescript")
                (tsx-ts-mode :language-id "typescriptreact"))
               . (lambda (&rest _)
                   (append '("typescript-language-server" "--stdio")
                           (unless (file-remote-p default-directory)
                             (list :initializationOptions
                                   (list :tsserver
                                         (list :fallbackPath
                                               (expand-file-name
                                                "tools/node/node_modules/typescript/lib/tsserver.js"
                                                user-emacs-directory)))))))))
(add-to-list 'eglot-server-programs
             '(((c-mode :language-id "c")
                (c-ts-mode :language-id "c")
                (c++-mode :language-id "cpp")
                (c++-ts-mode :language-id "cpp"))
               . ("clangd" "--background-index" "--clang-tidy")))
(add-to-list 'eglot-server-programs '(lua-mode . ("lua-language-server")))

(defun lcw-start-language-tools ()
  "Start installed local servers after directory-local settings."
  (when (derived-mode-p 'python-mode 'python-ts-mode)
    (lcw-python-setup))
  ;; Remote tools live on the host/container. Start explicitly with C-c l l.
  (when (and (not noninteractive) (not (file-remote-p default-directory))
             (cond
              ((derived-mode-p 'python-mode 'python-ts-mode)
               (executable-find "pyright-langserver"))
              ((derived-mode-p 'js-mode 'js-ts-mode 'typescript-ts-mode 'tsx-ts-mode)
               (executable-find "typescript-language-server"))
              ((derived-mode-p 'c-mode 'c-ts-mode 'c++-mode 'c++-ts-mode)
               (executable-find "clangd"))
              ((derived-mode-p 'lua-mode)
               (executable-find "lua-language-server"))))
    (eglot-ensure)))

(add-hook 'hack-local-variables-hook #'lcw-start-language-tools)

(defun lcw-language-auto-completion ()
  "Enable automatic completion in graphical language-server buffers."
  (when (and (display-graphic-p) (fboundp 'corfu-mode))
    (setq-local corfu-auto (eglot-managed-p))
    (corfu-mode -1)
    (corfu-mode 1)))

(add-hook 'eglot-managed-mode-hook #'lcw-language-auto-completion)

(defun lcw-format-buffer ()
  "Format Python with Ruff, JS/TS with Prettier, Elisp with indentation.
Other modes use Eglot (including clangd formatting for C/C++).
Run on the current host/container, preserving the buffer on failure."
  (interactive)
  (let* ((python-p (derived-mode-p 'python-mode 'python-ts-mode))
         (web-p (derived-mode-p 'js-mode 'js-ts-mode 'typescript-ts-mode 'tsx-ts-mode))
         (filename (file-local-name (or buffer-file-name
                                       (if python-p "stdin.py" "stdin.js"))))
         (program (cond (python-p "ruff") (web-p "prettier")))
         (args (if python-p (list "format" "--stdin-filename" filename "-")
                 (list "--stdin-filepath" filename))))
    (if (not program)
        (if (derived-mode-p 'emacs-lisp-mode 'lisp-interaction-mode)
            (indent-region (point-min) (point-max))
          (call-interactively #'eglot-format-buffer))
      (let ((input (make-nearby-temp-file ".emacs-format-"))
            (output (generate-new-buffer " *formatter-output*")))
        (unwind-protect
            (progn
              (write-region (point-min) (point-max) input nil 'silent)
              (if (zerop (apply #'process-file program (file-local-name input)
                                (list output t) nil args))
                  (replace-buffer-contents output)
                (user-error "Formatter failed: %s"
                            (with-current-buffer output (buffer-string)))))
          (delete-file input)
          (kill-buffer output))))))

(keymap-global-set "C-c l f" #'lcw-format-buffer)

(defun lcw-python-test (whole-project)
  "Run pytest for this file, or with WHOLE-PROJECT for the whole project."
  (interactive "P")
  (unless (derived-mode-p 'python-mode 'python-ts-mode)
    (user-error "Open a Python file first"))
  (save-some-buffers)
  (let* ((python (lcw-python-executable))
         (target (unless whole-project
                   (or buffer-file-name (user-error "Save the test file first"))))
         (default-directory (lcw-project-root)))
    (compile (concat (shell-quote-argument python) " -m pytest -q"
                     (when target
                       (concat " " (shell-quote-argument
                                    (file-local-name target))))))))

(keymap-global-set "C-c p t" #'lcw-python-test)

(defun lcw-python-lint ()
  "Run Ruff checks on the project in a compilation buffer."
  (interactive)
  (save-some-buffers)
  (let ((default-directory (lcw-project-root)))
    (compile "ruff check --output-format concise .")))

(keymap-global-set "C-c l c" #'lcw-python-lint)

(use-package dape
  :if (locate-library "dape")
  :bind (("<f5>" . dape)
         ("<f9>" . dape-breakpoint-toggle)
         ("C-c D d" . dape)
         ("C-c D b" . dape-breakpoint-toggle)
         ("<f10>" . dape-next)
         ("C-c D n" . dape-next)
         ("<f11>" . dape-step-in)
         ("S-<f11>" . dape-step-out)
         ("C-c D i" . dape-step-in)
         ("C-c D o" . dape-step-out)
         ("C-c D c" . dape-continue)
         ("C-c D q" . dape-quit))
  :custom
  (dape-buffer-window-arrangement 'right)
  :config
  ;; Local adapter is isolated; the debuggee uses the project's Python.
  (dolist (name '(debugpy debugpy-module))
    (let ((config (alist-get name dape-configs)))
      (setq config
            (plist-put config 'command
                       (lambda ()
                         (if (file-remote-p default-directory)
                             (lcw-python-executable)
                           (expand-file-name "tools/python/bin/python"
                                             user-emacs-directory)))))
      (setq config (plist-put config 'command-args '("-m" "debugpy.adapter")))
      (cl-remf config 'port)
      (setq config (plist-put config :python #'lcw-python-executable))
      (setf (alist-get name dape-configs) config)))
  (add-hook 'dape-start-hook #'save-some-buffers))

(with-eval-after-load 'tramp
  (require 'tramp-container)
  (add-to-list 'tramp-remote-path 'tramp-own-remote-path))

(provide 'init-programming)
;;; init-programming.el ends here
