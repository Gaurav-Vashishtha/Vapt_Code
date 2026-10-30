class OrderStatsController < AuthenticatedController
  def summary
    render json: stats.summary
  end

  def orders
    filter = OrderMetrics::Stats::FILTERS.key?(params[:filter]) ? params[:filter] : "all"
    render json: stats.orders(filter: filter, cursor: params[:cursor])
  end

  private

  def stats
    OrderMetrics::Stats.new(@shop, from: params[:from], to: params[:to], days: params[:days])
  end
end
