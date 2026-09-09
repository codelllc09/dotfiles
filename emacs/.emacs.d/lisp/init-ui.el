;;; init-ui.el --- Frames, tabs, themes, fonts, and icons -*- lexical-binding: t; -*-

(when (fboundp 'menu-bar-mode)
  (menu-bar-mode -1))
(when (fboundp 'tool-bar-mode)
  (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode)
  (scroll-bar-mode -1))
(when (fboundp 'horizontal-scroll-bar-mode)
  (horizontal-scroll-bar-mode -1))
(column-number-mode 1)

;; Give the frame content some breathing room and keep split windows distinct.
;; The default applies to future frames; set-frame-parameter updates this one.
(add-to-list 'default-frame-alist '(vertical-scroll-bars . nil))
(add-to-list 'default-frame-alist '(horizontal-scroll-bars . nil))
(add-to-list 'default-frame-alist '(internal-border-width . 15))
(set-frame-parameter nil 'internal-border-width 15)
(setq window-divider-default-right-width 1
      window-divider-default-bottom-width 2)
(window-divider-mode 1)

(defface lcw-terminal-header-label
  '((t (:inherit header-line :foreground "#89b4fa" :weight bold)))
  "Face for the terminal panel label and working directory.")

(defface lcw-terminal-header-hint
  '((t (:inherit header-line :foreground "#6c7086")))
  "Face for the terminal panel's quiet key hint.")

;; A tab-bar tab is a workspace/window layout. Its icon follows the buffer that
;; represents the workspace, like the program icon in the WezTerm tab title.
(defun lcw-tab-bar-tab-buffer (tab)
  "Return the representative live buffer for TAB."
  (if (eq (car tab) 'current-tab)
      (window-buffer (selected-window))
    (let ((point-marker (alist-get 'wc-point tab)))
      (or (and (markerp point-marker) (marker-buffer point-marker))
          (seq-find #'buffer-live-p (alist-get 'wc-bl tab))
          (get-buffer (alist-get 'name tab))))))

(defun lcw-tab-bar-tab-name-format-icon (name tab _index)
  "Prefix TAB's NAME with an icon for its representative buffer."
  (let* ((buffer (lcw-tab-bar-tab-buffer tab))
         (icon (and buffer
                    (fboundp 'nerd-icons-icon-for-buffer)
                    (with-current-buffer buffer
                      (nerd-icons-icon-for-buffer)))))
    ;; Let the active/inactive tab face color the icon together with the name.
    (concat (if (and (stringp icon) (not (string-empty-p icon)))
                (substring-no-properties icon)
              "◇")
            " " name)))

(defun lcw-tab-bar-tab-name-format-padding (name _tab _index)
  "Add compact horizontal breathing room around a tab NAME."
  (concat " " name " "))

(defun lcw-tab-bar-tab-name-format-status (name tab _index)
  "Prefix NAME with a clear active or inactive workspace marker."
  (concat (if (eq (car tab) 'current-tab) "● " "· ") name))

(defun lcw-apply-ui-faces ()
  "Style tabs, contextual headers, and window boundaries."
  (set-face-attribute 'tab-bar nil
                      :inherit 'default
                      :background "#181825"
                      :foreground "#6c7086"
                      :box nil)
  (set-face-attribute 'tab-bar-tab nil
                      :inherit 'tab-bar
                      :background "#313244"
                      :foreground "#cdd6f4"
                      :weight 'bold
                      :overline "#89b4fa"
                      :box '(:line-width (6 . 3) :color "#313244"))
  (set-face-attribute 'tab-bar-tab-inactive nil
                      :inherit 'tab-bar
                      :background "#181825"
                      :foreground "#6c7086"
                      :weight 'normal
                      :overline nil
                      :box '(:line-width (6 . 3) :color "#181825"))
  (set-face-attribute 'header-line nil
                      :inherit 'mode-line-inactive
                      :background "#181825"
                      :foreground "#a6adc8"
                      :box nil)
  (set-face-attribute 'lcw-terminal-header-label nil
                      :inherit 'header-line
                      :foreground "#89b4fa"
                      :weight 'bold)
  (set-face-attribute 'lcw-terminal-header-hint nil
                      :inherit 'header-line
                      :foreground "#6c7086")
  (dolist (face '(window-divider
                  window-divider-first-pixel
                  window-divider-last-pixel))
    (set-face-attribute face nil :foreground "#45475a")))

;; Keep the bar hidden until a second workspace exists. Unlike the default,
;; compact tabs follow their title width instead of filling the entire frame.
(use-package tab-bar
  :ensure nil
  :custom
  (tab-bar-show 1)
  (tab-bar-auto-width nil)
  (tab-bar-tab-hints t)
  (tab-bar-separator "")
  (tab-bar-close-button-show nil)
  (tab-bar-tab-name-format-functions
   '(lcw-tab-bar-tab-name-format-icon
     tab-bar-tab-name-format-hints
     lcw-tab-bar-tab-name-format-status
     tab-bar-tab-name-format-close-button
     lcw-tab-bar-tab-name-format-padding
     tab-bar-tab-name-format-face))
  :config
  (lcw-apply-ui-faces)
  (tab-bar-mode 1)
  (tab-bar-history-mode 1))

;; Buffers are selected through consult-buffer, so a persistent tab line would
;; duplicate that workflow and consume a row in every window.
(defun lcw-disable-tab-line-in-all-buffers ()
  "Disable Tab Line globally and in buffers restored from an old desktop."
  (global-tab-line-mode -1)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when tab-line-mode
        (tab-line-mode -1)))))

(use-package tab-line
  :ensure nil
  :config
  (lcw-disable-tab-line-in-all-buffers))

;; Reserve the top row of each window for contextual information. Keep the
;; initial content deliberately small until header-line/mode-line roles settle.
(setq-default header-line-format
              '(" " mode-line-buffer-identification " "))

;; Curated dark-theme lineup. C-c T previews themes through consult-theme;
;; M-x lcw-load-theme switches directly.
(add-to-list 'custom-theme-load-path
             (expand-file-name "themes/github-dark/" user-emacs-directory))

(use-package doom-themes
  :if (locate-library "doom-themes")
  :config
  (doom-themes-org-config))

(use-package catppuccin-theme
  :if (locate-library "catppuccin-theme")
  :custom
  (catppuccin-flavor 'mocha))

(defvar lcw-default-theme 'catppuccin
  "Theme loaded at startup.
Popular picks: catppuccin, doom-one, doom-dracula, modus-vivendi,
nord, gruvbox, solarized-dark, github-dark.")

(defun lcw-load-theme (theme)
  "Disable enabled themes, then load THEME without confirmation."
  (interactive
   (list (read (completing-read "Load theme: "
                                (mapcar #'symbol-name
                                        (custom-available-themes))))))
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme theme t)
  (lcw-apply-ui-faces))

(cond ((memq lcw-default-theme (custom-available-themes))
       (lcw-load-theme lcw-default-theme))
      ((memq 'github-dark (custom-available-themes))
       (lcw-load-theme 'github-dark)))

;; Use an explicitly monospaced font in graphical frames, including daemon clients.
(defvar lcw-code-font-family "Maple Mono NF CN"
  "Monospaced font used for source code.")

(defun lcw-apply-code-font (&optional frame)
  "Apply the code font to graphical FRAME without changing its font size."
  (let ((frame (or frame (selected-frame))))
    (when (display-graphic-p frame)
      (when (find-font (font-spec :family lcw-code-font-family) frame)
        (set-face-attribute 'default frame :family lcw-code-font-family)
        (set-face-attribute 'fixed-pitch frame :family lcw-code-font-family)
        (dolist (script '(han kana cjk-misc bopomofo))
          (set-fontset-font t script
                            (font-spec :family lcw-code-font-family)
                            frame))))))

(add-hook 'after-make-frame-functions #'lcw-apply-code-font)
(lcw-apply-code-font)

;; nerd-icons reads Nerd Font v3 codepoints directly from Maple Mono NF CN.
(use-package nerd-icons
  :if (locate-library "nerd-icons")
  :custom
  (nerd-icons-font-family lcw-code-font-family))

(use-package nerd-icons-dired
  :if (locate-library "nerd-icons-dired")
  :hook (dired-mode . nerd-icons-dired-mode))

(use-package nerd-icons-corfu
  :if (locate-library "nerd-icons-corfu")
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

(use-package nerd-icons-completion
  :if (locate-library "nerd-icons-completion")
  :after marginalia
  :config
  (nerd-icons-completion-mode))

(provide 'init-ui)
;;; init-ui.el ends here
