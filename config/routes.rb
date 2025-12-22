Rails.application.routes.draw do
  # ================== Devise (Usuarios) ==================
  devise_for :users

  # ================== Root según sesión ==================
  devise_scope :user do
    unauthenticated { root to: "devise/sessions#new" }
    authenticated   { root to: "dashboard#home", as: :authenticated_root }
  end

  # ================== Clientes (CRUD membresías) ==================
  resources :clients

  # ================== Ventas (registro/consulta/corte/ajustes) ==================
  resources :sales, only: [ :index, :show ] do
    collection do
      get  :corte
      get  :adjustments
      post :unlock_adjustments
      post :reverse_transaction
    end
  end

  # ================== Productos (Backoffice CRUD) ==================
  resources :products

  # ================== Pago de Servicios (NUEVO) ==================
  resources :expenses, only: [ :new, :create, :destroy ]

  # ================== Carrito / Tienda ==================
  resource :cart, only: [ :show ], controller: :cart do
    post :add        # params: product_id
    post :increment  # params: product_id
    post :decrement  # params: product_id
    post :remove     # params: product_id
    post :checkout   # params: payment_method (cash|transfer)
  end

  # ================== Reports ==================
  get "reports/daily_export",        to: "reports#daily_export",        as: :reports_daily_export   # CSV
  get "reports/daily_export_excel",  to: "reports#daily_export_excel",  as: :reports_daily_export_excel # XLSX
  get "history",                     to: "reports#history",             as: :history
  get "closeout",                    to: "reports#closeout",            as: :closeout

  # ================== Admin: gestión de usuarios ==================
  namespace :admin do
    resources :users, only: [ :index, :new, :create ]
  end

  # ================== Griselle Cart (carrito especial) ==================
  resource :griselle_cart, only: [ :show ], controller: :griselle_cart do
    post :add
    post :increment
    post :decrement
    post :remove
    post :checkout
  end

  # ================== Cobrar Mensualidad ==================
  get  "memberships",          to: "memberships#new",      as: :memberships
  post "memberships/checkout", to: "memberships#checkout", as: :memberships_checkout
end
