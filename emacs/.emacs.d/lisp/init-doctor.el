;;; init-doctor.el --- Read-only configuration diagnostics -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'package)

(declare-function treesit-ready-p "treesit.c")
(require 'seq)
(require 'tabulated-list)

(defconst lcw-doctor-required-programs '("git" "rg")
  "Programs required by core workflows.")

(defconst lcw-doctor-optional-programs
  '("ruff" "pyright-langserver" "typescript-language-server"
    "clangd" "lua-language-server" "codex-acp" "pi-acp")
  "Programs used by optional language and agent integrations.")

(defun lcw-doctor--nearest-existing-directory (directory)
  "Return the nearest existing parent of DIRECTORY."
  (let ((directory (file-name-as-directory (expand-file-name directory)))
        parent)
    (while (and (not (file-directory-p directory))
                (not (equal directory
                            (setq parent
                                  (file-name-directory
                                   (directory-file-name directory))))))
      (setq directory parent))
    directory))

(defun lcw-doctor--directory-writable-p (directory)
  "Return non-nil when DIRECTORY exists or could be created by Emacs."
  (file-writable-p (lcw-doctor--nearest-existing-directory directory)))

(defun lcw-doctor--collect ()
  "Return diagnostic rows as (STATUS COMPONENT DETAIL) lists."
  (let (rows)
    (cl-labels ((add (status component detail)
                  (push (list status component detail) rows)))
      (add (if (>= emacs-major-version 30) 'pass 'fail)
           "Emacs"
           (format "%s (configuration expects 30 or newer)" emacs-version))

      (dolist (mode '((which-key-mode . "Which-key")
                      (editorconfig-mode . "EditorConfig")))
        (add (if (and (boundp (car mode)) (symbol-value (car mode)))
                 'pass 'warn)
             (cdr mode)
             (if (and (boundp (car mode)) (symbol-value (car mode)))
                 "enabled"
               "not enabled")))

      (let ((missing
             (seq-remove #'package-installed-p
                         (append lcw-ide-packages lcw-theme-packages))))
        (add (if missing 'warn 'pass)
             "Packages"
             (if missing
                 (format "missing: %s; run M-x lcw-install-ide-packages"
                         (mapconcat #'symbol-name missing ", "))
               "all configured packages are installed")))

      (let ((consult-ready
             (and (require 'consult nil t)
                  (fboundp 'consult--buffer-query)
                  (fboundp 'consult--buffer-state)
                  (boundp 'consult-source-buffer))))
        (add (if consult-ready 'pass 'fail)
             "Consult tab grouping"
             (if consult-ready
                 "compatible Consult APIs are available"
               "Consult changed; tab grouping needs attention")))

      (dolist (program lcw-doctor-required-programs)
        (add (if (executable-find program) 'pass 'fail)
             (format "Program: %s" program)
             (or (executable-find program) "not found in PATH")))
      (dolist (program lcw-doctor-optional-programs)
        (add (if (executable-find program) 'pass 'warn)
             (format "Optional: %s" program)
             (or (executable-find program) "not found; related feature is unavailable")))

      (let ((missing-languages
             (seq-remove (lambda (language) (treesit-ready-p language t))
                         '(c cpp python javascript typescript tsx))))
        (add (if missing-languages 'warn 'pass)
             "Tree-sitter grammars"
             (if missing-languages
                 (format "missing: %s"
                         (mapconcat #'symbol-name missing-languages ", "))
               "all configured grammars are ready")))

      (let ((module
             (and (boundp 'module-file-suffix)
                  (locate-file (concat "vterm-module" module-file-suffix)
                               load-path))))
        (add (if (and (locate-library "vterm") module) 'pass 'warn)
             "Vterm"
             (cond
              ((not (locate-library "vterm")) "package is missing")
              (module (format "module: %s" (abbreviate-file-name module)))
              (t "package exists but its native module was not found"))))

      (if (display-graphic-p)
          (dolist (font '("Maple Mono NF CN" "Symbols Nerd Font Mono"))
            (add (if (find-font (font-spec :family font)) 'pass 'warn)
                 (format "Font: %s" font)
                 (if (find-font (font-spec :family font))
                     "available"
                   "not found")))
        (add 'warn "Fonts" "not checked in a terminal-only session"))

      (dolist (directory
               (list user-emacs-directory
                     (expand-file-name "state/" user-emacs-directory)
                     lcw-desktop-directory
                     (expand-file-name "state/agent-shell/" user-emacs-directory)))
        (add (if (lcw-doctor--directory-writable-p directory) 'pass 'fail)
             "Writable directory"
             (abbreviate-file-name directory)))

      (dolist (binding '(("C-x b" . lcw-consult-buffer)
                         ("C-c n s" . lcw-search-project-todos)
                         ("C-c z z" . hs-toggle-hiding)))
        (let ((actual (key-binding (kbd (car binding)))))
          (add (if (eq actual (cdr binding)) 'pass 'warn)
               (format "Key: %s" (car binding))
               (format "%s" (or actual "unbound"))))))
    (nreverse rows)))

(define-derived-mode lcw-doctor-mode tabulated-list-mode "LCW Doctor"
  "Major mode for the read-only LCW configuration health report."
  (setq tabulated-list-format
        [("Status" 8 t)
         ("Component" 28 t)
         ("Detail" 0 nil)])
  (setq tabulated-list-padding 2
        tabulated-list-sort-key nil)
  (tabulated-list-init-header))

(defun lcw-doctor--status-string (status)
  "Return a colored display string for STATUS."
  (pcase status
    ('pass (propertize "PASS" 'face 'success))
    ('warn (propertize "WARN" 'face 'warning))
    ('fail (propertize "FAIL" 'face 'error))))

(defun lcw-doctor--refresh ()
  "Refresh the current LCW Doctor report."
  (let* ((rows (lcw-doctor--collect))
         (pass (seq-count (lambda (row) (eq (car row) 'pass)) rows))
         (warn (seq-count (lambda (row) (eq (car row) 'warn)) rows))
         (fail (seq-count (lambda (row) (eq (car row) 'fail)) rows)))
    (setq tabulated-list-entries
          (cl-loop for row in rows
                   for id from 0
                   collect
                   (list id (vector (lcw-doctor--status-string (nth 0 row))
                                    (nth 1 row)
                                    (nth 2 row)))))
    (setq header-line-format
          (format " LCW Doctor: %d passed, %d warnings, %d failures   (g to refresh)"
                  pass warn fail))
    (tabulated-list-print t)))

(defun lcw-doctor ()
  "Display a read-only health report for this Emacs configuration."
  (interactive)
  (let ((buffer (get-buffer-create "*LCW Doctor*")))
    (with-current-buffer buffer
      (lcw-doctor-mode)
      (setq-local revert-buffer-function
                  (lambda (&rest _) (lcw-doctor--refresh)))
      (lcw-doctor--refresh))
    (pop-to-buffer buffer)))

(provide 'init-doctor)
;;; init-doctor.el ends here
