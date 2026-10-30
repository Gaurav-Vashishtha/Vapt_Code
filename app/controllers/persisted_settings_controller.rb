class PersistedSettingsController < ApplicationController
  before_action :set_persisted_setting, only: %i[ show update destroy ]

  # GET /persisted_settings
  # GET /persisted_settings.json
  def index
    @persisted_settings = PersistedSetting.all
  end

  # GET /persisted_settings/1
  # GET /persisted_settings/1.json
  def show
  end

  # POST /persisted_settings
  # POST /persisted_settings.json
  def create
    @persisted_setting = PersistedSetting.new(persisted_setting_params)

    if @persisted_setting.save
      render :show, status: :created, location: @persisted_setting
    else
      render json: @persisted_setting.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /persisted_settings/1
  # PATCH/PUT /persisted_settings/1.json
  def update
    if @persisted_setting.update(persisted_setting_params)
      render :show, status: :ok, location: @persisted_setting
    else
      render json: @persisted_setting.errors, status: :unprocessable_entity
    end
  end

  # DELETE /persisted_settings/1
  # DELETE /persisted_settings/1.json
  def destroy
    @persisted_setting.destroy
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_persisted_setting
      @persisted_setting = PersistedSetting.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def persisted_setting_params
      params.require(:persisted_setting).permit(:test_order_count, :shop_id)
    end
end
