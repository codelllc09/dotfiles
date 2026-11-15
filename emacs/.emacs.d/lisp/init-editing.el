;;; init-editing.el --- Editing behavior and in-buffer tools -*- lexical-binding: t; -*-

(declare-function corfu-popupinfo-mode "corfu.el")

(require 'subr-x)

;;; Files, backups, and global behavior --------------------------------------

;; Keep backups and auto-saves out of source directories.
(let ((backup-dir (expand-file-name "backups/" user-emacs-directory))
      (autosave-dir (expand-file-name "auto-saves/" user-emacs-directory)))
  (make-directory backup-dir t)
  (make-directory autosave-dir t)
  (setq backup-directory-alist `(("." . ,backup-dir))
        auto-save-file-name-transforms `((".*" ,autosave-dir t))
        backup-by-copying t
        version-control t
        kept-new-versions 6
        kept-old-versions 2
        delete-old-versions t))

(setq inhibit-startup-screen t
      use-short-answers t
      ring-bell-function #'ignore
      tab-always-indent 'complete
      read-extended-command-predicate #'command-completion-default-include-p
      compilation-scroll-output 'first-error
      large-file-warning-threshold (* 10 1000 1000))
(setq-default indent-tabs-mode nil
              tab-width 4)

;;; Genuine unmodified state after undo --------------------------------------

;; Emacs normally remembers that an edit happened, even when the user types
;; text and then deletes it again.  Keep a lightweight saved-content baseline
;; so an exactly restored buffer becomes genuinely unmodified again.
(defvar-local lcw-saved-content-size nil
  "Character count of this buffer at its last read or save.")

(defvar-local lcw-saved-content-hash nil
  "Hash of this buffer's text at its last read or save.")

(defun lcw-buffer-content-hash ()
  "Return a SHA-256 hash of all text in the current buffer."
  (save-restriction
    (widen)
    (secure-hash 'sha256 (current-buffer) (point-min) (point-max))))

(defun lcw-clear-modified-if-content-restored (&rest _ignored)
  "Clear the modified flag when text matches the last saved baseline.
The cheap size test avoids hashing during ordinary insertion and deletion."
  (when (and buffer-file-name
             (buffer-modified-p)
             lcw-saved-content-hash
             (= (buffer-size) lcw-saved-content-size)
             (equal (lcw-buffer-content-hash) lcw-saved-content-hash))
    (set-buffer-modified-p nil)
    (force-mode-line-update)))

(defun lcw-record-saved-content ()
  "Record the current file buffer text as its saved baseline."
  (when buffer-file-name
    (setq-local lcw-saved-content-size (buffer-size)
                lcw-saved-content-hash (lcw-buffer-content-hash))))

(defun lcw-enable-content-restore-check ()
  "Enable saved-content comparison after edits in the current buffer."
  (when buffer-file-name
    (add-hook 'after-change-functions
              #'lcw-clear-modified-if-content-restored nil t)))

(defun lcw-disable-content-restore-check ()
  "Disable saved-content comparison after edits in the current buffer."
  (remove-hook 'after-change-functions
               #'lcw-clear-modified-if-content-restored t))

(defun lcw-read-local-file-content-state (file coding)
  "Return FILE's decoded (SIZE . HASH) using CODING.
This helper deliberately avoids reading remote files during configuration
reloads; remote buffers establish their baseline when opened or saved."
  (when (and file (not (file-remote-p file)) (file-readable-p file))
    (condition-case nil
        (let ((coding-system-for-read coding))
          (with-temp-buffer
            (insert-file-contents file)
            (cons (buffer-size) (lcw-buffer-content-hash))))
      (file-error nil))))

(defun lcw-initialize-saved-content-tracking (&optional buffer)
  "Install saved-content tracking in BUFFER, including after a reload."
  (with-current-buffer (or buffer (current-buffer))
    (when buffer-file-name
      (cond
       ((not (buffer-modified-p))
        (lcw-record-saved-content))
       ((not (file-remote-p buffer-file-name))
        (if-let* ((state
                   (lcw-read-local-file-content-state
                    buffer-file-name buffer-file-coding-system)))
            (setq-local lcw-saved-content-size (car state)
                        lcw-saved-content-hash (cdr state))
          ;; A newly created, not-yet-saved file has an empty disk baseline.
          (setq-local lcw-saved-content-size 0
                      lcw-saved-content-hash (secure-hash 'sha256 "")))
        (lcw-clear-modified-if-content-restored)))
      (lcw-enable-content-restore-check))))

(add-hook 'find-file-hook #'lcw-record-saved-content 95)
(add-hook 'find-file-hook #'lcw-enable-content-restore-check 96)
(add-hook 'after-save-hook #'lcw-record-saved-content 95)
(add-hook 'after-revert-hook #'lcw-record-saved-content 95)
(add-hook 'after-revert-hook #'lcw-enable-content-restore-check 96)

;; Reloading this module should fix existing local buffers immediately without
;; opening a network connection for currently modified TRAMP buffers.
(dolist (buffer (buffer-list))
  (lcw-initialize-saved-content-tracking buffer))

;;; Ubiquitous minor modes ---------------------------------------------------

(show-paren-mode 1)
(electric-pair-mode 1)
(delete-selection-mode 1)
(save-place-mode 1)
(savehist-mode 1)
(recentf-mode 1)
(global-auto-revert-mode 1)
(which-key-mode 1)
(editorconfig-mode 1)
(repeat-mode 1)
(setq display-line-numbers-type t
      display-line-numbers-width 3)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)
(add-hook 'text-mode-hook #'display-line-numbers-mode)
(add-hook 'prog-mode-hook #'hl-line-mode)

;;; Pathological long lines and huge files -----------------------------------

;; Protect the UI from pathological long lines and files too large to load whole.
(use-package so-long
  :ensure nil
  :config
  (global-so-long-mode 1))

(use-package vlf-setup
  :if (locate-library "vlf-setup")
  :demand t
  :bind (("C-c v" . vlf))
  :custom
  (vlf-application 'ask)
  (vlf-batch-size 1000000))

;;; In-buffer tools: snippets, completion sources, cursors, parens -----------

(use-package yasnippet
  :if (locate-library "yasnippet")
  :hook (prog-mode . yas-minor-mode)
  :custom
  (yas-snippet-dirs (list (expand-file-name "snippets" user-emacs-directory)))
  :config
  (yas-reload-all))

(defun lcw-add-cape-completions ()
  "Add file and buffer-word completion as fallbacks in this buffer."
  (add-hook 'completion-at-point-functions #'cape-file 90 t)
  (add-hook 'completion-at-point-functions #'cape-dabbrev 100 t))

(use-package cape
  :if (locate-library "cape")
  :hook ((prog-mode . lcw-add-cape-completions)
         (text-mode . lcw-add-cape-completions)))

(use-package multiple-cursors
  :if (locate-library "multiple-cursors")
  :bind (("C->" . mc/mark-next-like-this)
         ("C-<" . mc/mark-previous-like-this)
         ("C-c C-<" . mc/mark-all-like-this)
         ("C-S-c C-S-c" . mc/edit-lines)
         ("C-\"" . mc/skip-to-next-like-this)
         ("C-:" . mc/skip-to-previous-like-this))
  :custom
  (mc/list-file (expand-file-name "state/multiple-cursors-lists.el"
                                   user-emacs-directory)))

(use-package paredit
  :if (locate-library "paredit")
  :commands paredit-mode)

;; Emacs 30 Corfu popups need a graphical frame. Terminals retain built-in
;; completion (C-M-i / TAB), without requiring a terminal popup extension.
(defun lcw-enable-corfu-in-gui ()
  "Enable Corfu for graphical programming buffers."
  (when (display-graphic-p)
    (corfu-mode 1)))

(use-package corfu
  :if (locate-library "corfu")
  :hook (prog-mode . lcw-enable-corfu-in-gui)
  :custom
  (corfu-cycle t)
  (corfu-auto nil)
  (corfu-preview-current nil)
  :config
  (corfu-popupinfo-mode 1))

(keymap-global-set "C-," #'duplicate-dwim)

(provide (quote init-editing))
;;; init-editing.el ends here
