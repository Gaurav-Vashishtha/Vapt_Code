class LocksController < ApplicationController
  before_action :set_lock, only: %i[ show update destroy ]

  # GET /locks
  # GET /locks.json
  def index
    @locks = Lock.all
  end

  # GET /locks/1
  # GET /locks/1.json
  def show
  end

  # POST /locks
  # POST /locks.json
  def create
    @lock = Lock.new(lock_params)

    if @lock.save
      render :show, status: :created, location: @lock
    else
      render json: @lock.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /locks/1
  # PATCH/PUT /locks/1.json
  def update
    if @lock.update(lock_params)
      render :show, status: :ok, location: @lock
    else
      render json: @lock.errors, status: :unprocessable_entity
    end
  end

  # DELETE /locks/1
  # DELETE /locks/1.json
  def destroy
    @lock.destroy
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_lock
      @lock = Lock.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def lock_params
      params.require(:lock).permit(:value)
    end
end
