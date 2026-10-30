import React, { Component } from 'react'
import PropTypes from 'prop-types'
import {Button, ColorPicker, TextField, Popover} from '@shopify/polaris';
import {hsbToHex, rgbToHsb} from '@shopify/polaris';

// interchange will always be hex

export default class HexColorPicker extends Component {
  static propTypes = {
    color: PropTypes.string,
    label: PropTypes.string,
    onChange: PropTypes.func
  }

  static defaultProps = {
    color: "#000000"
  }

  getColorValue(color) {
    // Ensure we always have a valid hex color
    if (!color || color === "" || color === null || color === undefined) {
      return "#000000";
    }
    return color;
  }

  constructor(props){
    super(props);
    this.state = {
      isColorPickerOpen: false,
      textValue: this.getColorValue(props.color)
    };
    this.toggleColorPicker = this.toggleColorPicker.bind(this);
    this.closeColorPicker = this.closeColorPicker.bind(this);
    this.handleTextChange = this.handleTextChange.bind(this);
  }

  // https://stackoverflow.com/questions/5623838/rgb-to-hex-and-hex-to-rgb
  hexToRgb(hex) {
    var shorthandRegex = /^#?([a-f\d])([a-f\d])([a-f\d])$/i;
    hex = hex.replace(shorthandRegex, function(m, r, g, b) {
        return r + r + g + g + b + b;
    });

    var result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    return result ? {
        red: parseInt(result[1], 16),
        green: parseInt(result[2], 16),
        blue: parseInt(result[3], 16)
    } : null;
  }
  toggleColorPicker(){
    this.setState({isColorPickerOpen: !this.state.isColorPickerOpen});
  }
  // Popover calls this to dismiss, so it has to close rather than toggle:
  // toggling would reopen the picker on a dismiss that raced the state.
  closeColorPicker(){
    this.setState({isColorPickerOpen: false});
  }
  formatHexToHsb(hex){
    const rgb = this.hexToRgb(hex);
    if (!rgb) {
      // Return a default HSB value (black) if hex conversion fails
      return { hue: 0, saturation: 0, brightness: 0 };
    }
    return rgbToHsb(rgb);
  }

  componentWillReceiveProps(nextProps) {
    if(nextProps.color !== this.props.color){
      this.setState({textValue: this.getColorValue(nextProps.color)});
    } 
  }

  handleTextChange(value){
    this.setState({textValue: value});
    try{
      let color = this.hexToRgb(value);
      if(color){
        this.props.onChange(value);
      }
    }catch(err){
    }
  }
  
  render() {
    const safeColor = this.getColorValue(this.props.color);
    return (
      <div>
        <Popover
          active={this.state.isColorPickerOpen}
          onClose={this.closeColorPicker}
          activator={
            <TextField
              label={this.props.label}
              onChange={this.handleTextChange}
              value={this.state.textValue}
              autoComplete="off"
              connectedRight={
                <Button
                  onClick={this.toggleColorPicker}
                  disclosure={this.state.isColorPickerOpen ? "up" : "down"}
                  accessibilityLabel={`Pick a colour${
                    this.props.label ? ` for ${this.props.label}` : ""
                  }`}
                >
                  {/* A hex field on its own does not read as a colour control,
                      so the swatch is sized to be the obvious thing to click.
                      The border keeps a white or very light colour visible
                      against the button. */}
                  <div
                    className="color-preview"
                    style={{
                      backgroundColor: safeColor,
                      width: "32px",
                      height: "20px",
                      borderRadius: "4px",
                      border: "1px solid rgba(0, 0, 0, 0.25)",
                      boxShadow: "inset 0 0 0 1px rgba(255, 255, 255, 0.35)",
                    }}
                  />
                </Button>
              }
            />
          }
        >
          <ColorPicker onChange={(color) => this.props.onChange(hsbToHex(color))} color={this.formatHexToHsb(safeColor)} />
        </Popover>
      </div>
    )
  }
}