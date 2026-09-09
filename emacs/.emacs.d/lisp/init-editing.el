;;; init-editing.el --- Editing behavior and in-buffer tools -*- lexical-binding: t; -*-

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

;; Markdown remains a portable editing format; Obsidian manages the vault.
(defun lcw-markdown-limit-wiki-search ()
  "Recognize wiki links without recursively scanning large repositories."
  (setq-local markdown-wiki-link-search-type nil
              markdown-wiki-link-search-subdirectories nil
              markdown-wiki-link-search-parent-directories nil))

(use-package markdown-mode
  :if (locate-library "markdown-mode")
  :mode (("\\.\\(?:md\\|markdown\\)\\'" . gfm-mode))
  :hook (gfm-mode . lcw-markdown-limit-wiki-search)
  :custom
  (markdown-fontify-code-blocks-natively t)
  (markdown-enable-wiki-links t)
  (markdown-enable-math t)
  (markdown-hide-markup nil)
  (markdown-hide-urls nil)
  :config
  ;; markdown-mode registers a generic .md rule while loading. Keep GFM first.
  (let ((entry '("\\.\\(?:md\\|markdown\\)\\'" . gfm-mode)))
    (setq auto-mode-alist (delete entry auto-mode-alist))
    (push entry auto-mode-alist)))

;; PDF Tools loads when a PDF is opened and never invokes a system package manager.
(use-package pdf-tools
  :if (locate-library "pdf-tools")
  :defer t
  :init
  (setq pdf-view-display-size 'fit-width)
  (pdf-loader-install nil t)
  :hook (pdf-view-mode . (lambda () (display-line-numbers-mode -1))))

(provide 'init-editing)
;;; init-editing.el ends here
